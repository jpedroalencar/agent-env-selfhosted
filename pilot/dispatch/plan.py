"""
ExecutionPlan — the single contract between Platform intelligence and Hermes execution.

Minimal edition: only the fields needed for the first end-to-end request.

Contract: ExecutionPlan v1.0 (frozen).
Do NOT add or remove fields without a Contract Review.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import List


_VALID_MEMORY_TIERS = frozenset({"persistent", "working", "none"})


@dataclass(frozen=True)
class ExecutionPlan:
    """A validated plan for Hermes Runtime execution.

    Produced by Platform Dispatch. Consumed by the Hermes Adapter.
    """

    intent: str
    profile: str
    question: str
    skills: List[str] = field(default_factory=list)
    memory_tier: str = "working"
    knowledge_providers: List[str] = field(default_factory=list)
    preloaded_context: str = ""


class PlanValidationError(ValueError):
    """Raised when an ExecutionPlan fails pre-execution validation."""


def validate_plan(plan: ExecutionPlan) -> None:
    """Validate an ExecutionPlan before execution.

    Enforces ExecutionPlan v1.0 Invariant 1:
    'A plan is never executed without validation.'

    Does NOT modify the ExecutionPlan contract. Only checks that
    required fields are present and valid.
    """
    if not plan.profile:
        raise PlanValidationError("ExecutionPlan has no profile")

    if not isinstance(plan.skills, list):
        raise PlanValidationError(
            f"ExecutionPlan skills must be a list, got {type(plan.skills).__name__}"
        )

    if plan.memory_tier not in _VALID_MEMORY_TIERS:
        raise PlanValidationError(
            f"ExecutionPlan memory_tier must be one of "
            f"{sorted(_VALID_MEMORY_TIERS)}, got '{plan.memory_tier}'"
        )

    if not isinstance(plan.knowledge_providers, list):
        raise PlanValidationError(
            f"ExecutionPlan knowledge_providers must be a list, "
            f"got {type(plan.knowledge_providers).__name__}"
        )
