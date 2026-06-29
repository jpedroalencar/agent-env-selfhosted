"""
Knowledge Orchestrator — coordinates execution of Knowledge Providers.

It replaces the previous static provider calls in gateway. The orchestrator:
- Queries the Knowledge Registry for the providers listed in the ExecutionPlan.
- Instantiates each provider.
- Executes the provider with the appropriate request parameters.
- Filters out empty artifacts.
- Returns a deterministic list of KnowledgeArtifacts preserving the order in
  ``plan.knowledge_providers``.

No provider may invoke another provider; orchestration is the sole responsibility
for ordering and collection.
"""

from __future__ import annotations

from typing import List

from pilot.provider_registry import get_provider


def _intent_to_vault_selection(intent: str, question: str = "") -> str:
    """Map intent + request text to a VaultProvider selection string.

    The mapping mirrors the logic previously embedded in ``gateway.py``.
    It raises ``ValueError`` for intents that should not use the Vault.
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
    # Casual intents and others do not use Vault.
    raise ValueError(f"Intent '{intent}' should not use VaultProvider")


def run(plan, intent: str, question: str) -> List:
    """Execute all knowledge providers declared in ``plan``.

    Args:
        plan: ExecutionPlan instance containing ``knowledge_providers`` list.
        intent: The platform intent derived from the classifier.
        question: Original user request text.

    Returns:
        List of ``KnowledgeArtifact`` objects, already filtered for non‑empty
        content and ordered according to the plan.
    """
    artifacts = []
    for provider_name in plan.knowledge_providers:
        ProviderCls = get_provider(provider_name)
        provider = ProviderCls()
        # Each built‑in provider expects a different argument shape.
        if provider_name == "memory":
            artifact = provider.produce_artifact(f"{intent} {question}")
        elif provider_name == "vault":
            try:
                selection = _intent_to_vault_selection(intent, question)
            except ValueError:
                # Intent not suitable for Vault – skip this provider.
                continue
            artifact = provider.produce_artifact(selection)
        else:
            # For future providers that follow the generic contract.
            artifact = provider.produce_artifact(intent)
        if artifact.content.strip():
            artifacts.append(artifact)
    return artifacts
