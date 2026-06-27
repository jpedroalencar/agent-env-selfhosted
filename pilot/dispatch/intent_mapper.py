"""
IntentMapper — maps RequestShape to Platform intent strings.

Simple lookup table. Deterministic. No model inference.

This replaces the Hermes Context Planner's rule engine, dependency
resolver, and plan compiler. The Platform's routing.yaml (via
ConfigProvider) handles what those 1,100 lines of Hermes code did.
"""

from __future__ import annotations

from pilot.dispatch._types import RequestShape

# ── Shape → Intent mapping ───────────────────────────────────────────────────
#
# Maps every RequestShape to a Platform intent that ConfigProvider
# can look up in routing.yaml.
#
# CONFIG_CHANGE and HERMES_SELF_SERVICE currently map to 'ambiguous'
# because the routing config has no dedicated intent for them.
# A future routing rule could add 'hermes_config'.

_SHAPE_TO_INTENT = {
    RequestShape.CODE_CHANGE: "code_change",
    RequestShape.CODE_QUESTION: "code_question",
    RequestShape.CONFIG_CHANGE: "ambiguous",          # no dedicated intent yet
    RequestShape.HERMES_SELF_SERVICE: "ambiguous",     # no dedicated intent yet
    RequestShape.RESEARCH: "research",
    RequestShape.CASUAL_CONVERSATION: "casual",
    RequestShape.MULTI_STEP_WORKFLOW: "multi_step",
    RequestShape.AMBIGUOUS: "ambiguous",
}


def shape_to_intent(shape: RequestShape) -> str:
    """Map a RequestShape to a Platform intent.

    Every shape maps to exactly one intent. Unknown shapes
    fall back to 'ambiguous' (orchestrator).
    """
    return _SHAPE_TO_INTENT.get(shape, "ambiguous")
