"""
Platform Gateway — entry point for all user requests.

Orchestrates the complete Platform → Adapter → Model pipeline.

Pipeline:
  User Request → Parser → Classifier → ConfigProvider.lookup(intent)
  → ExecutionPlan → Knowledge Providers → Context System
  → Prompt Builder → Hermes Runtime
"""

from __future__ import annotations

from adapters.hermes.model import call_model
from pilot.config_provider import ConfigProvider
from pilot.context.system import assemble_context
from pilot.dispatch._classifier import classify
from pilot.dispatch._parser import parse
from pilot.dispatch.intent_mapper import shape_to_intent
from pilot.dispatch.plan import ExecutionPlan, validate_plan
from pilot.knowledge.providers.memory import MemoryProvider
from pilot.prompt.builder import build_prompt


def handle_request(question: str) -> dict:
    """Process a user request through the complete pipeline.

    Deterministic: same input always produces the same output.
    No model calls until the final step.

    Returns a dict with the full pipeline trace.
    """
    # ── Step 1: Parse — extract signals from raw text ──
    parsed = parse(question)
    shape = classify(parsed)

    # ── Step 2: Map shape → Platform intent ──
    intent = shape_to_intent(shape)

    # ── Step 3: Load configuration ──
    config = ConfigProvider()

    # ── Step 4: Create ExecutionPlan ──
    rule = config.lookup(intent)
    plan = ExecutionPlan(
        intent=intent,
        profile=rule.profile if rule else "orchestrator",
        question=question,
        skills=rule.skills if rule else [],
        memory_tier=rule.memory_tier if rule else "none",
        knowledge_providers=rule.knowledge_providers if rule else [],
    )

    # ── Step 5: Validate plan (contract requirement) ──
    validate_plan(plan)

    # ── Step 6: Produce KnowledgeArtifacts from all providers ──
    config_artifact = config.produce_artifact(intent)
    memory = MemoryProvider()
    memory_artifact = memory.produce_artifact(intent)
    artifacts = [config_artifact, memory_artifact]

    # ── Step 7: Assemble context ──
    context = assemble_context(artifacts)

    # ── Step 8: Build prompt ──
    prompt = build_prompt(context, question)

    # ── Step 9: Call model ──
    response = call_model(prompt)

    return {
        "parse": {
            "shape": shape.name,
            "has_question": parsed.has_question,
            "imperative_verbs": parsed.imperative_verbs,
            "urls": parsed.urls,
        },
        "intent": intent,
        "plan": {
            "profile": plan.profile,
            "skills": plan.skills,
            "memory_tier": plan.memory_tier,
            "knowledge_providers": plan.knowledge_providers,
        },
        "artifacts": [
            {"source": a.source, "content": a.content[:200]}
            for a in artifacts
        ],
        "context": context[:300],
        "response": response,
    }
