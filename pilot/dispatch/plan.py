"""
ExecutionPlan — the single contract between Platform intelligence and Hermes execution.

Minimal edition: only the fields needed for the first end-to-end request.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import List


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
