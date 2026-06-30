"""
HermesAdapter — concrete implementation of AgentAdapter for Hermes Runtime.

Translates the Platform's execute() call into a Hermes model invocation.
Owns model selection, retries, and timeouts.

Single responsibility: bridge AgentAdapter interface → Hermes model call.
Does NOT: classify, plan, build prompts, or modify Hermes source code.
"""
from __future__ import annotations

import logging
from typing import Optional

from adapters.hermes.model import call_model
from pilot.dispatch.plan import ExecutionPlan

log = logging.getLogger(__name__)


class HermesAdapter:
    """AgentAdapter implementation backed by Hermes Runtime.

    Delegates to adapters.hermes.model.call_model for the actual
    API call. The Platform depends only on the AgentAdapter protocol,
    never on this class directly.

    The adapter accepts an ExecutionPlan at construction — this is
    Hermes-internal plumbing. The AgentAdapter interface itself
    remains plan-agnostic (execute(prompt) -> str).

    Usage:
        plan = ExecutionPlan(...)
        adapter = HermesAdapter(plan=plan)
        response = adapter.execute("What is 2+2?")

    Configuration:
        plan: The validated ExecutionPlan governing this execution.
        model: Model name passed to call_model (default: deepseek-v4-pro)
    """

    def __init__(self, *, plan: ExecutionPlan, model: str = "deepseek-v4-pro"):
        self._plan = plan
        self._model = model

    def execute(self, prompt: str) -> str:
        """Execute a prompt via Hermes Runtime.

        Args:
            prompt: Fully-assembled prompt string.

        Returns:
            Model response text.

        Raises:
            RuntimeError: If the model call fails.
            TimeoutError: If the execution times out.
        """
        if not prompt:
            raise RuntimeError("Cannot execute empty prompt")

        log.info("HermesAdapter.execute(model=%s, prompt_len=%d)", self._model, len(prompt))

        try:
            response = call_model(prompt, plan=self._plan, model=self._model)
        except RuntimeError:
            # Re-raise as-is — call_model already formats the error
            raise
        except Exception as exc:
            raise RuntimeError(f"HermesAdapter execution failed: {exc}") from exc

        if not response:
            log.warning("HermesAdapter received empty response for prompt_len=%d", len(prompt))

        return response

    def __repr__(self) -> str:
        return f"HermesAdapter(model={self._model!r})"
