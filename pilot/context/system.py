"""
Context System — assembles context from the ExecutionPlan and ConfigProvider.

Minimal edition: hardcoded assembly for the first end-to-end request.
No abstraction. No caching. No provider registry.
"""

from __future__ import annotations

from pilot.config_provider import ConfigProvider
from pilot.dispatch.plan import ExecutionPlan
from pilot.knowledge.artifact import KnowledgeArtifact


def assemble_context(plan: ExecutionPlan, config: ConfigProvider) -> str:
    """Assemble context from the ExecutionPlan.

    Loads routing information from ConfigProvider and formats it
    as structured context for the model.

    Shortcut: hardcoded to config provider only. Later phases will
    add vault, memory, and web providers.
    """
    rule = config.lookup(plan.intent)

    if rule is None:
        config_context = f"No routing rule found for intent '{plan.intent}'."
    else:
        config_context = (
            f"Intent: {plan.intent}\n"
            f"Profile: {rule.profile}\n"
            f"Skills: {', '.join(rule.skills) if rule.skills else '(none)'}\n"
            f"Memory tier: {rule.memory_tier}\n"
            f"Knowledge providers: {', '.join(rule.knowledge_providers) if rule.knowledge_providers else '(none)'}"
        )

    return config_context


def produce_artifact(plan: ExecutionPlan, config: ConfigProvider) -> KnowledgeArtifact:
    """Produce a KnowledgeArtifact from the config provider.

    Shortcut: single provider. Later phases will query multiple providers
    and merge results.
    """
    rule = config.lookup(plan.intent)

    if rule is None:
        content = f"No routing rule for '{plan.intent}'."
    else:
        content = (
            f"Intent '{plan.intent}' routes to profile '{rule.profile}' "
            f"with skills {rule.skills}, memory tier '{rule.memory_tier}', "
            f"and knowledge providers {rule.knowledge_providers}."
        )

    return KnowledgeArtifact(source="config", content=content)
