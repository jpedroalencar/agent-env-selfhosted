"""
RequestClassifier — maps ParsedRequest signals to a RequestShape.

Uses a decision tree defined in ``classifier_rules.yaml``.  Every
possible ``ParsedRequest`` maps to exactly one ``RequestShape``.
The tree is evaluated top-down; the first matching rule wins.
If no rule matches, ``RequestShape.AMBIGUOUS`` is returned.

The classifier does NOT use any model or embedding — it is pure
regex + boolean logic evaluated against the parsed signals.
"""

from __future__ import annotations

import os
import re
from typing import Optional

from ._parser import _contains_code_terms, _contains_hermes_terms
from ._types import ParsedRequest, RequestShape

# ── Built-in classifier rules ────────────────────────────────────────────────
#
# The decision tree is defined here as a list of (condition, shape) pairs.
# Rules are evaluated in order; the first match wins.
#
# A ``condition`` is a callable ``(ParsedRequest) -> bool``.
#
# For maintainability, complex conditions are factored into named
# helper functions.  Adding a new shape or tuning classification
# behavior means adding or reordering rules here — no YAML parsing
# overhead at runtime.

# Shorter aliases for readability
_SHAPE = RequestShape


def _classifier_rules():
    """Return the ordered list of classifier rules.

    Each rule is (name, condition_fn, shape).  First match wins.
    """
    return [
        # ── Priority 1: Explicit Hermes self-service ────────────────────────
        (
            "hermes_self_service",
            lambda p: (
                _contains_hermes_terms(p.raw_text)
                or "hermes-agent" in [s.lower() for s in p.explicit_skill_mentions]
                or p.command_prefix in ("config", "model", "tools", "skills", "cron",
                                        "gateway", "restart", "profile")
            ),
            _SHAPE.HERMES_SELF_SERVICE,
        ),

        # ── Priority 2: Config change ───────────────────────────────────────
        (
            "config_change",
            lambda p: (
                bool(p.imperative_verbs)
                and any(
                    term in p.raw_text.lower()
                    for term in ("config", "setting", "provider", "api_key", ".env",
                                 "gateway", "model", "profile", "fallback")
                )
            ),
            _SHAPE.CONFIG_CHANGE,
        ),

        # ── Priority 3: Multi-step workflow ─────────────────────────────────
        (
            "multi_step_workflow",
            lambda p: (
                p.command_prefix is not None
                or any(
                    phrase in p.raw_text.lower()
                    for phrase in ("step by step", "workflow", "pipeline",
                                   "do this then", "first then",
                                   "plan out", "orchestrate",
                                   "first create", "then implement",
                                   "first we", "then we")
                )
                # Also match "first...then" across clauses
                or (
                    "first" in (first_word := p.raw_text.lower().split()[0] if p.raw_text.split() else "")
                    and "then" in p.raw_text.lower()
                )
            ),
            _SHAPE.MULTI_STEP_WORKFLOW,
        ),

        # ── Priority 4: Code change ─────────────────────────────────────────
        (
            "code_change",
            lambda p: (
                bool(p.imperative_verbs)
                and (
                    bool(p.file_paths)
                    or _contains_code_terms(p.raw_text)
                )
            ),
            _SHAPE.CODE_CHANGE,
        ),

        # ── Priority 5: Code question ───────────────────────────────────────
        (
            "code_question",
            lambda p: (
                p.has_question
                and (
                    bool(p.file_paths)
                    or _contains_code_terms(p.raw_text)
                )
            ),
            _SHAPE.CODE_QUESTION,
        ),

        # ── Priority 6: Research ────────────────────────────────────────────
        (
            "research",
            lambda p: (
                p.has_question
                and not p.file_paths
                and not _contains_code_terms(p.raw_text)
                and not bool(p.imperative_verbs)
            ),
            _SHAPE.RESEARCH,
        ),

        # ── Priority 7: Casual conversation (catch-all for short messages) ──
        (
            "casual_conversation",
            lambda p: 0 < p.word_count <= 15 and not p.file_paths,
            _SHAPE.CASUAL_CONVERSATION,
        ),
    ]


def classify(parsed: ParsedRequest) -> RequestShape:
    """Classify a parsed request into exactly one RequestShape.

    Evaluates the decision tree top-down.  The first rule whose
    condition returns ``True`` determines the shape.

    Args:
        parsed: A ``ParsedRequest`` from ``RequestParser.parse()``.

    Returns:
        The determined ``RequestShape``.  Always non-None — if no
        rule matches, returns ``RequestShape.AMBIGUOUS``.
    """
    for name, condition, shape in _classifier_rules():
        try:
            if condition(parsed):
                return shape
        except Exception:
            # A buggy condition should not crash the pipeline.
            # Log and continue to the next rule.
            continue

    return _SHAPE.AMBIGUOUS


def explain_classification(parsed: ParsedRequest) -> str:
    """Return a human-readable explanation of the classification path.

    For debugging and diagnostic use.  Evaluates every rule and reports
    which matched and which didn't.

    Args:
        parsed: A ``ParsedRequest`` from ``RequestParser.parse()``.

    Returns:
        Multi-line diagnostic string.
    """
    lines = [f"Classification trace for: {parsed.raw_text[:80]}..."]
    lines.append(f"  Signals: has_question={parsed.has_question}, "
                 f"imperative={parsed.imperative_verbs}, "
                 f"files={len(parsed.file_paths)}, "
                 f"urls={len(parsed.urls)}, "
                 f"cmd={parsed.command_prefix}")
    lines.append("  Rule evaluation:")

    matched = False
    for name, condition, shape in _classifier_rules():
        try:
            result = condition(parsed)
        except Exception as exc:
            lines.append(f"    [{name}] ERROR: {exc}")
            continue
        marker = "✓" if result else "✗"
        lines.append(f"    [{name}] -> {shape.name} {marker}")
        if result:
            matched = True

    if not matched:
        lines.append("  No rule matched -> AMBIGUOUS")
    return "\n".join(lines)
