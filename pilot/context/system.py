"""
Context System — assembles context from the ExecutionPlan and ConfigProvider.

Minimal edition: hardcoded assembly for the first end-to-end request.
No abstraction. No caching. No provider registry.

Contracts: the Context System only assembles context.
KnowledgeProviders (e.g. ConfigProvider.produce_artifact) produce artifacts.
"""

from __future__ import annotations

from pilot.config_provider import ConfigProvider
from pilot.dispatch.plan import ExecutionPlan


def assemble_context(plan: ExecutionPlan, config: ConfigProvider) -> str:
    """Assemble context from the ExecutionPlan.

    Loads routing information from ConfigProvider and formats it
    as structured context for the model.

    Shortcut: hardcoded to config provider only. Later phases will
    add vault, memory, and web providers.
    """
    rule = config.lookup(plan.intent)

    if rule is None:
        return f"No routing rule found for intent '{plan.intent}'."

    return (
        f"Intent: {plan.intent}\n"
        f"Profile: {rule.profile}\n"
        f"Skills: {', '.join(rule.skills) if rule.skills else '(none)'}\n"
        f"Memory tier: {rule.memory_tier}\n"
        f"Knowledge providers: {', '.join(rule.knowledge_providers) if rule.knowledge_providers else '(none)'}"
    )
