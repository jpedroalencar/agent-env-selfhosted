"""
Data structures for the Platform Dispatch subsystem.

Pruned from Hermes context_planner/_types.py.
Only types used by _parser and _classifier are retained.

Discarded: RetrievalType, RetrievalItem, RetrievalPlan, Rule, RuleCondition,
RuleSource, RawRetrievalAction, OrderedRetrievalAction — coupled to the
RetrievalPlan paradigm, replaced by ExecutionPlan.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Any, Dict, List, Optional


# ── Enums ────────────────────────────────────────────────────────────────────


class RequestShape(Enum):
    """Finite, stable taxonomy of request shapes.

    Every possible ParsedRequest maps to exactly one RequestShape.
    Classification is purely rule-based — no model inference.
    """

    CODE_CHANGE = auto()           # imperative verbs + file paths
    CODE_QUESTION = auto()         # question markers + file paths / code terms
    CONFIG_CHANGE = auto()         # mentions of config, provider, setting
    HERMES_SELF_SERVICE = auto()   # explicit "hermes" mentions or hermes-agent ref
    RESEARCH = auto()              # question markers, no code signals
    CASUAL_CONVERSATION = auto()   # short, no signals
    MULTI_STEP_WORKFLOW = auto()   # command prefix or workflow language
    AMBIGUOUS = auto()              # contradictory or insufficient signals


# ── Input data structures ────────────────────────────────────────────────────


@dataclass
class SessionSnapshot:
    """Ambient session state passed to the planner."""

    platform: str                   # "telegram", "discord", "cli", ...
    user_id: str
    profile: str                    # active Hermes profile name
    conversation_id: str            # thread / channel / DM id
    locale: Optional[str] = None    # detected language hint (optional)


@dataclass
class ContextPlannerInput:
    """Complete input to the Context Planner."""

    user_message: str
    session_snapshot: SessionSnapshot
    available_skills: List[str] = field(default_factory=list)
    active_toolsets: List[str] = field(default_factory=list)
    hints: Optional[Dict[str, Any]] = None


# ── Intermediate data structure ──────────────────────────────────────────────


@dataclass
class ParsedRequest:
    """Output of the RequestParser — signals extracted from raw text."""

    raw_text: str
    explicit_skill_mentions: List[str] = field(default_factory=list)
    command_prefix: Optional[str] = None
    urls: List[str] = field(default_factory=list)
    file_paths: List[str] = field(default_factory=list)
    mentioned_entities: List[str] = field(default_factory=list)
    has_question: bool = False
    imperative_verbs: List[str] = field(default_factory=list)
    char_length: int = 0
    word_count: int = 0
    script_families: List[str] = field(default_factory=list)
    truncated_input: bool = False
