"""
Platform Gateway — entry point for all user requests.

Orchestrates the complete Platform → Adapter → Model pipeline.
Hardcoded wiring for the first end-to-end request.

Shortcuts:
  - No HTTP server. Direct function call.
  - No intent classification. Single known intent (financial_analysis).
  - No async. Synchronous.
  - No error handling beyond basic try/except.
"""

from __future__ import annotations

from adapters.hermes.model import call_model
from pilot.config_provider import ConfigProvider
from pilot.context.system import assemble_context, produce_artifact
from pilot.dispatch.plan import ExecutionPlan
from pilot.prompt.builder import build_prompt


def handle_request(question: str) -> dict:
    """Process a user request through the complete pipeline.

    Hardcoded for the first end-to-end test:
      "Which profile should handle a financial analysis request?"

    Returns a dict with the full pipeline trace.
    """
    # ── Step 1: Classify intent (hardcoded) ──
    intent = "financial_analysis"

    # ── Step 2: Load configuration ──
    config = ConfigProvider()

    # ── Step 3: Create ExecutionPlan ──
    rule = config.lookup(intent)
    plan = ExecutionPlan(
        intent=intent,
        profile=rule.profile if rule else "orchestrator",
        question=question,
        skills=rule.skills if rule else [],
        memory_tier=rule.memory_tier if rule else "none",
        knowledge_providers=rule.knowledge_providers if rule else [],
    )

    # ── Step 4: Produce KnowledgeArtifact ──
    artifact = produce_artifact(plan, config)

    # ── Step 5: Assemble context ──
    context = assemble_context(plan, config)

    # ── Step 6: Build prompt ──
    prompt = build_prompt(context, question)

    # ── Step 7: Call model ──
    response = call_model(prompt)

    return {
        "intent": intent,
        "plan": {
            "profile": plan.profile,
            "skills": plan.skills,
            "memory_tier": plan.memory_tier,
            "knowledge_providers": plan.knowledge_providers,
        },
        "artifact": {
            "source": artifact.source,
            "content": artifact.content,
        },
        "context": context,
        "prompt": prompt,
        "response": response,
    }
