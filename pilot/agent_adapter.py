"""
AgentAdapter — the minimal interface between Platform intelligence
and any agent runtime (Hermes, LangChain, CrewAI, etc.).

The Platform depends ONLY on this interface. Concrete runtimes
provide their own implementation. This keeps the Platform decoupled
from runtime internals.

Minimal edition: one method, one responsibility.
    execute(prompt) → str

No streaming. No tool callbacks. No model selection.
The adapter decides how to run the prompt — the Platform
only asks it to run.
"""
from __future__ import annotations

from typing import Protocol, runtime_checkable


@runtime_checkable
class AgentAdapter(Protocol):
    """Interface for agent runtime execution.

    Any class implementing ``execute(prompt: str) -> str`` satisfies
    this protocol via structural subtyping. No inheritance required.

    Invariants:
        1. execute() is synchronous and blocking.
        2. Returns the full response text, or raises on failure.
        3. The adapter owns model selection, retries, and timeouts.
        4. The Platform never calls anything besides execute().
    """

    def execute(self, prompt: str) -> str:
        """Execute a prompt and return the response text.

        Args:
            prompt: The fully-assembled prompt string. Contains system
                    message, context, and user question.

        Returns:
            The model's response as a plain string.

        Raises:
            RuntimeError: If the runtime fails to produce a response.
            TimeoutError: If the execution exceeds the adapter's timeout.
        """
        ...
