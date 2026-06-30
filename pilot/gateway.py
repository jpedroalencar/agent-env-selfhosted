"""
Platform Gateway — entry point for all user requests.

Orchestrates the complete Platform → Adapter → Model pipeline.
Pipeline:
  User Request → Parser → Classifier → ConfigProvider.lookup(intent)
  → ExecutionPlan → Knowledge Providers → Context System
  → Prompt Builder → AgentAdapter.execute()

The Gateway depends on the AgentAdapter *interface* (pilot.agent_adapter),
not on any concrete runtime implementation. The concrete adapter is
injected via the ``adapter`` parameter, defaulting to HermesAdapter
when none is provided.
"""
from __future__ import annotations

from typing import Optional

from pilot.agent_adapter import AgentAdapter
from pilot.config_provider import ConfigProvider
from pilot.context.system import assemble_context
from pilot.dispatch._classifier import classify
from pilot.dispatch._parser import parse
from pilot.dispatch.intent_mapper import shape_to_intent
from pilot.dispatch.plan import ExecutionPlan, validate_plan
from pilot.prompt.builder import build_prompt


def _intent_to_vault_selection(intent: str, question: str = "") -> str:
    """Map Platform intent plus request text to VaultProvider selection string.

    The Gateway chooses which providers run; provider-specific relevance selection
    stays inside VaultProvider. The request text is passed through as the existing
    provider key so VaultProvider can match titles/tags/metadata deterministically.
    """
    query = question.strip()

    if intent.startswith("research"):
        return f"summary:{query}" if query else "summary"

    if intent.startswith("financial_analysis") or intent.startswith("stock"):
        return f"summary:{query}" if query else "summary"

    if intent.startswith("dev"):
        return f"summary:{query}" if query else "summary"

    if intent.startswith("operations") or intent.startswith("ops"):
        return f"summary:{query}" if query else "summary"

    # Casual intents don't use VaultProvider
    raise ValueError(f"Intent '{intent}' should not use VaultProvider")


def handle_request(question: str, adapter: Optional[AgentAdapter] = None) -> dict:
    """Process a user request through the complete pipeline.

    Deterministic: same input always produces the same output.
    No model calls until the final step.

    Args:
        question: Raw user request text.
        adapter: AgentAdapter implementation. Defaults to HermesAdapter.

    Returns:
        A dict with the full pipeline trace.
    """
    # adapter is injected by the caller; plan is created below and
    # threaded into HermesAdapter when no adapter is provided.

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

    # ── Step 6: Produce KnowledgeArtifacts from all providers via Context Orchestrator ──
    config_artifact = config.produce_artifact(intent)
    # Run KnowledgeOrchestrator to collect artifacts from registered providers
    from pilot.context.knowledge_orchestrator import run as orchestrator_run
    provider_artifacts = orchestrator_run(plan, intent, question)
    # Apply ContextSelector (currently a no‑op) for future metadata‑first lazy loading
    from pilot.context.context_selector import select_artifacts
    provider_artifacts = select_artifacts(plan, provider_artifacts)
    artifacts = [config_artifact] + provider_artifacts

    # ── Step 7: Assemble context ──
    context, budget_report = assemble_context(artifacts)

    # ── Step 8: Build prompt ──
    prompt = build_prompt(context, question)

    # ── Step 9: Execute via AgentAdapter (interface, not concrete class) ──
    if adapter is None:
        from adapters.hermes.executor import HermesAdapter
        adapter = HermesAdapter(plan=plan)
    response = adapter.execute(prompt)

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
        "budget_report": {
            "entries": [
                {
                    "provider": e.provider,
                    "characters": e.characters,
                    "estimated_tokens": e.estimated_tokens,
                    "percentage": e.percentage,
                }
                for e in budget_report.entries
            ],
            "total_context_characters": budget_report.total_context_characters,
            "total_context_tokens": budget_report.total_context_tokens,
        },
        "response": response,
    }
