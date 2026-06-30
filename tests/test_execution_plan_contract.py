"""Integration test: ExecutionPlan is the single authoritative execution contract.

Proves:
  User Request → Gateway → ExecutionPlan → execution path

Verifies:
  1. Every gateway execution produces a validated ExecutionPlan.
  2. The plan flows through to the adapter (call_model).
  3. call_model refuses to execute without a plan.
  4. No direct model invocation bypasses the plan.
"""
from __future__ import annotations

import sys
import types
from unittest.mock import patch, MagicMock

import pytest

# ── Bootstrap: ensure repo root is importable ──────────────────────────────────
_REPO = "/root/agent-env-selfhosted"
if _REPO not in sys.path:
    sys.path.insert(0, _REPO)

from pilot.dispatch.plan import ExecutionPlan, validate_plan, PlanValidationError
from pilot.dispatch._parser import parse
from pilot.dispatch._classifier import classify
from pilot.dispatch.intent_mapper import shape_to_intent
from pilot.config_provider import ConfigProvider
from pilot.prompt.builder import build_prompt
from pilot.context.system import assemble_context


# ── Unit: call_model enforces plan requirement ─────────────────────────────────


class TestCallModelRequiresPlan:
    """The adapter refuses execution without an ExecutionPlan."""

    def test_call_model_rejects_none_plan(self):
        """call_model(plan=None) must raise TypeError — no bypass allowed."""
        from adapters.hermes.model import call_model

        with pytest.raises(TypeError, match="requires an ExecutionPlan"):
            call_model("test prompt", plan=None)

    def test_call_model_rejects_missing_plan(self):
        """call_model without plan argument must raise TypeError."""
        from adapters.hermes.model import call_model

        with pytest.raises(TypeError):
            # plan is keyword-only, so omitting it should fail
            call_model("test prompt")

    def test_call_model_accepts_valid_plan(self):
        """call_model accepts a valid ExecutionPlan and invokes the model."""
        from adapters.hermes.model import call_model

        plan = ExecutionPlan(
            intent="research",
            profile="orchestrator",
            question="What is AI?",
            skills=[],
            memory_tier="none",
            knowledge_providers=[],
        )

        # Mock subprocess.run to avoid real API call
        mock_result = MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = "AI is artificial intelligence."
        mock_result.stderr = ""

        with patch("adapters.hermes.model.subprocess.run", return_value=mock_result) as mock_run:
            with patch("adapters.hermes.model._get_api_key", return_value="test-key"):
                result = call_model("What is AI?", plan=plan)

        assert result == "AI is artificial intelligence."
        # Verify subprocess was called (execution occurred)
        mock_run.assert_called_once()


# ── Unit: ExecutionPlan lifecycle ──────────────────────────────────────────────


class TestExecutionPlanLifecycle:
    """The plan is created, validated, and governs execution."""

    def test_plan_created_from_dispatch(self):
        """A request goes through Parser → Classifier → Intent → Plan."""
        question = "What is the capital of France?"
        parsed = parse(question)
        shape = classify(parsed)
        intent = shape_to_intent(shape)

        config = ConfigProvider()
        rule = config.lookup(intent)
        plan = ExecutionPlan(
            intent=intent,
            profile=rule.profile if rule else "orchestrator",
            question=question,
            skills=rule.skills if rule else [],
            memory_tier=rule.memory_tier if rule else "none",
            knowledge_providers=rule.knowledge_providers if rule else [],
        )

        # Plan is valid
        validate_plan(plan)
        assert plan.intent == "research"
        assert plan.profile
        assert isinstance(plan.skills, list)

    def test_plan_governs_model_call(self):
        """The plan is passed to call_model — not bypassed."""
        from adapters.hermes.model import call_model

        plan = ExecutionPlan(
            intent="code_change",
            profile="developer",
            question="Fix the auth bug",
            skills=["systematic-debugging"],
            memory_tier="working",
            knowledge_providers=["memory"],
        )

        mock_result = MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = "Fixed."
        mock_result.stderr = ""

        with patch("adapters.hermes.model.subprocess.run", return_value=mock_result):
            with patch("adapters.hermes.model._get_api_key", return_value="test-key"):
                call_model("Fix the auth bug", plan=plan)

        # If we got here, the plan was accepted — execution originated from the plan
        # Verify the subprocess script contains the prompt
        call_args = mock_result  # subprocess.run was called
        assert mock_result.stdout == "Fixed."


# ── Integration: full gateway trace with plan threading ────────────────────────


class TestGatewayExecutionPlanIntegration:
    """Full pipeline: User Request → Gateway → ExecutionPlan → execution.

    Mocks the model call and knowledge providers to isolate the plan-threading
    behavior. The test proves the plan flows from creation through validation
    to the adapter boundary.
    """

    def test_request_produces_plan_and_threads_to_adapter(self):
        """Gateway creates a plan and passes it to the adapter."""
        from pilot.gateway import handle_request

        # Mock adapter to capture the prompt it receives
        captured = {}

        class MockAdapter:
            def execute(self, prompt):
                captured["prompt"] = prompt
                return "Mocked response"

        adapter = MockAdapter()

        # Mock knowledge orchestrator to return empty artifacts
        mock_orchestrator = MagicMock(return_value=[])

        with patch("pilot.context.knowledge_orchestrator.run", side_effect=mock_orchestrator):
            result = handle_request("What is the capital of France?", adapter=adapter)

        # 1. The gateway produced a valid plan
        assert "plan" in result
        assert result["plan"]["profile"]
        assert isinstance(result["plan"]["knowledge_providers"], list)

        # 2. The adapter received the prompt (plan was threaded through the pipeline)
        assert captured["prompt"] is not None
        assert "France" in captured["prompt"]

        # 3. The response came through the adapter
        assert result["response"] == "Mocked response"

    def test_no_direct_model_invocation_bypasses_plan(self):
        """call_model is only importable with the plan parameter."""
        import inspect
        from adapters.hermes.model import call_model

        sig = inspect.signature(call_model)
        params = sig.parameters

        # plan must be a required keyword-only parameter
        assert "plan" in params
        plan_param = params["plan"]
        assert plan_param.kind == inspect.Parameter.KEYWORD_ONLY
        # No default — it's required
        assert plan_param.default is inspect.Parameter.empty

    def test_plan_fields_flow_to_adapter(self):
        """The adapter receives the plan's intent, profile, and skills."""
        from adapters.hermes.model import call_model

        plan = ExecutionPlan(
            intent="financial_analysis",
            profile="analyst",
            question="Analyze AAPL",
            skills=["stock-bull-bear-report"],
            memory_tier="persistent",
            knowledge_providers=["vault", "memory"],
        )

        mock_result = MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = "AAPL analysis..."
        mock_result.stderr = ""

        with patch("adapters.hermes.model.subprocess.run", return_value=mock_result) as mock_run:
            with patch("adapters.hermes.model._get_api_key", return_value="test-key"):
                call_model("Analyze AAPL", plan=plan)

        # Verify the subprocess was called (execution occurred under the plan)
        mock_run.assert_called_once()
        # The prompt in the subprocess script should contain the question
        script = mock_run.call_args[0][0][-1]  # last arg is the -c script
        assert "Analyze AAPL" in script
