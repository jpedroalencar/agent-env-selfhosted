"""Tests for AgentAdapter interface, HermesAdapter, and pipeline flow.

Verifies:
    1. AgentAdapter is a valid Protocol
    2. HermesAdapter conforms to the interface
    3. Any class with execute(prompt)->str satisfies the protocol
    4. Pipeline flow: ExecutionPlan → AgentAdapter → response
    5. Gateway accepts adapter injection
    6. Error handling: empty prompts, failed execution

Run from /tmp:
    cd /tmp && PYTHONPATH=/root/agent-env-selfhosted \
        python3 -m pytest /root/agent-env-selfhosted/tests/test_agent_adapter.py -v
"""
from __future__ import annotations

import inspect
from unittest.mock import patch, MagicMock

import pytest

from pilot.agent_adapter import AgentAdapter
from pilot.dispatch.plan import ExecutionPlan, validate_plan


# ── Helpers ─────────────────────────────────────────────────────────────────


class EchoAdapter:
    """Minimal adapter that echoes the prompt back — for protocol testing."""

    def execute(self, prompt: str) -> str:
        return f"echo: {prompt}"


class FailingAdapter:
    """Adapter that always raises RuntimeError."""

    def execute(self, prompt: str) -> str:
        raise RuntimeError("model unavailable")


class TrackingAdapter:
    """Adapter that records every call for inspection."""

    def __init__(self):
        self.calls: list[str] = []

    def execute(self, prompt: str) -> str:
        self.calls.append(prompt)
        return f"ok:{len(self.calls)}"


class NotAnAdapter:
    """Deliberately does NOT satisfy AgentAdapter — no execute method."""

    def run(self, prompt: str) -> str:
        return "wrong method"


def _make_plan(**overrides) -> ExecutionPlan:
    """Create a valid ExecutionPlan with sensible defaults."""
    defaults = dict(
        intent="research",
        profile="research-analyst",
        question="test question",
        skills=[],
        memory_tier="working",
        knowledge_providers=[],
    )
    defaults.update(overrides)
    return ExecutionPlan(**defaults)


# ── 1. Protocol conformance ────────────────────────────────────────────────


class TestAgentAdapterProtocol:
    """AgentAdapter is a runtime_checkable Protocol."""

    def test_echo_adapter_satisfies_protocol(self):
        assert isinstance(EchoAdapter(), AgentAdapter)

    def test_failing_adapter_satisfies_protocol(self):
        assert isinstance(FailingAdapter(), AgentAdapter)

    def test_tracking_adapter_satisfies_protocol(self):
        assert isinstance(TrackingAdapter(), AgentAdapter)

    def test_not_an_adapter_rejected(self):
        assert not isinstance(NotAnAdapter(), AgentAdapter)

    def test_plain_dict_rejected(self):
        assert not isinstance({}, AgentAdapter)

    def test_string_rejected(self):
        assert not isinstance("hello", AgentAdapter)

    def test_any_class_with_execute_satisfies_protocol(self):
        """Structural subtyping: any class with execute(prompt)->str works."""

        class AdHoc:
            def execute(self, prompt: str) -> str:
                return "ad-hoc"

        assert isinstance(AdHoc(), AgentAdapter)


# ── 2. HermesAdapter unit tests ────────────────────────────────────────────


class TestHermesAdapter:
    """HermesAdapter delegates to model.call_model."""

    def test_conforms_to_protocol(self):
        from adapters.hermes.executor import HermesAdapter

        plan = _make_plan()
        assert isinstance(HermesAdapter(plan=plan), AgentAdapter)

    @patch("adapters.hermes.executor.call_model")
    def test_execute_delegates_to_call_model(self, mock_call):
        mock_call.return_value = "The answer is 42."
        plan = _make_plan()

        from adapters.hermes.executor import HermesAdapter

        adapter = HermesAdapter(plan=plan, model="deepseek-v4-pro")
        result = adapter.execute("What is 6*7?")

        assert result == "The answer is 42."
        mock_call.assert_called_once_with(
            "What is 6*7?", plan=plan, model="deepseek-v4-pro"
        )

    @patch("adapters.hermes.executor.call_model")
    def test_execute_passes_model_name(self, mock_call):
        mock_call.return_value = "response"
        plan = _make_plan()

        from adapters.hermes.executor import HermesAdapter

        adapter = HermesAdapter(plan=plan, model="custom-model")
        adapter.execute("test")

        mock_call.assert_called_once_with("test", plan=plan, model="custom-model")

    def test_execute_rejects_empty_prompt(self):
        from adapters.hermes.executor import HermesAdapter

        adapter = HermesAdapter(plan=_make_plan())
        with pytest.raises(RuntimeError, match="empty prompt"):
            adapter.execute("")

    def test_execute_rejects_none_prompt(self):
        from adapters.hermes.executor import HermesAdapter

        adapter = HermesAdapter(plan=_make_plan())
        with pytest.raises(RuntimeError, match="empty prompt"):
            adapter.execute(None)

    @patch("adapters.hermes.executor.call_model")
    def test_execute_propagates_runtime_error(self, mock_call):
        mock_call.side_effect = RuntimeError("API down")

        from adapters.hermes.executor import HermesAdapter

        adapter = HermesAdapter(plan=_make_plan())
        with pytest.raises(RuntimeError, match="API down"):
            adapter.execute("test")

    @patch("adapters.hermes.executor.call_model")
    def test_execute_wraps_unexpected_errors(self, mock_call):
        mock_call.side_effect = ValueError("unexpected")

        from adapters.hermes.executor import HermesAdapter

        adapter = HermesAdapter(plan=_make_plan())
        with pytest.raises(RuntimeError, match="execution failed"):
            adapter.execute("test")

    @patch("adapters.hermes.executor.call_model")
    def test_execute_returns_response(self, mock_call):
        mock_call.return_value = "platform-specific response"

        from adapters.hermes.executor import HermesAdapter

        adapter = HermesAdapter(plan=_make_plan())
        result = adapter.execute("hello")
        assert result == "platform-specific response"

    def test_repr(self):
        from adapters.hermes.executor import HermesAdapter

        adapter = HermesAdapter(plan=_make_plan(), model="test-model")
        assert repr(adapter) == "HermesAdapter(model='test-model')"


# ── 3. Pipeline flow: ExecutionPlan → AgentAdapter → response ──────────────


class TestPipelineFlow:
    """ExecutionPlan flows through AgentAdapter to produce a response."""

    def test_plan_to_response_with_echo(self):
        """Full pipeline using a mock adapter — no real API calls."""
        plan = _make_plan(
            intent="research",
            profile="research-analyst",
            question="What is Python?",
            preloaded_context="Python is a programming language.",
        )
        validate_plan(plan)

        adapter = EchoAdapter()
        prompt = f"Context: {plan.preloaded_context}\nQuestion: {plan.question}"
        response = adapter.execute(prompt)

        assert "What is Python?" in response
        assert "echo:" in response

    def test_plan_to_response_with_tracking(self):
        """TrackingAdapter records the prompt for verification."""
        plan = _make_plan(
            intent="code_change",
            profile="dev",
            question="Fix the bug",
        )
        validate_plan(plan)

        adapter = TrackingAdapter()
        prompt = f"Profile: {plan.profile}\nQuestion: {plan.question}"
        response = adapter.execute(prompt)

        assert response == "ok:1"
        assert len(adapter.calls) == 1
        assert "Fix the bug" in adapter.calls[0]

    def test_plan_validation_blocks_invalid_plan(self):
        """validate_plan rejects plans with missing profile."""
        plan = ExecutionPlan(
            intent="research",
            profile="",  # invalid
            question="test",
        )
        with pytest.raises(Exception):
            validate_plan(plan)

    def test_multiple_plans_through_same_adapter(self):
        """Adapter state survives across multiple plan executions."""
        adapter = TrackingAdapter()

        plans = [
            _make_plan(intent="research", question="Q1"),
            _make_plan(intent="code_change", question="Q2"),
            _make_plan(intent="casual", question="Q3"),
        ]

        for plan in plans:
            validate_plan(plan)
            adapter.execute(plan.question)

        assert len(adapter.calls) == 3
        assert adapter.calls == ["Q1", "Q2", "Q3"]


# ── 4. Gateway adapter injection ───────────────────────────────────────────


class TestGatewayAdapterInjection:
    """Gateway.handle_request accepts AgentAdapter parameter."""

    def test_gateway_accepts_custom_adapter(self):
        """handle_request accepts an adapter — no API call, just plumbing."""
        from pilot.gateway import handle_request

        sig = inspect.signature(handle_request)
        param = sig.parameters["adapter"]
        assert param.default is None  # Optional[AgentAdapter] = None

    def test_gateway_type_annotation(self):
        """handle_request's adapter parameter is typed as AgentAdapter."""
        from pilot.gateway import handle_request

        sig = inspect.signature(handle_request)
        param = sig.parameters["adapter"]
        assert "AgentAdapter" in str(param.annotation) or param.annotation is AgentAdapter

    def test_gateway_injects_mock_adapter(self):
        """Gateway routes prompt to injected adapter, bypassing real model."""
        from pilot.gateway import handle_request

        captured = {}

        class MockAdapter:
            def execute(self, prompt):
                captured["prompt"] = prompt
                return "mock-response"

        mock_orchestrator = MagicMock(return_value=[])

        with patch("pilot.context.knowledge_orchestrator.run", side_effect=mock_orchestrator):
            result = handle_request("What is AI?", adapter=MockAdapter())

        assert result["response"] == "mock-response"
        assert "AI" in captured["prompt"]
