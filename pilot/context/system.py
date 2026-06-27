"""
Context System — assembles context from KnowledgeArtifacts.

Minimal edition: accepts a list of artifacts and formats them.
No abstraction. No caching. No provider registry.

Contracts: the Context System only assembles context.
KnowledgeProviders produce artifacts. The Context System
receives them and formats them into the prompt.
"""

from __future__ import annotations

from pilot.knowledge.artifact import KnowledgeArtifact


def assemble_context(artifacts: list[KnowledgeArtifact]) -> str:
    """Assemble context from a list of KnowledgeArtifacts.

    Each artifact is formatted as a labeled block. Blocks are
    joined with double newlines. Empty artifacts are skipped.

    The Context System does not know or care which providers
    produced the artifacts — it only formats what it receives.
    """
    blocks: list[str] = []

    for artifact in artifacts:
        if not artifact.content.strip():
            continue

        label = _label_for(artifact.source)
        blocks.append(f"## {label}\n\n{artifact.content}")

    return "\n\n".join(blocks) if blocks else "(no context available)"


def _label_for(source: str) -> str:
    """Map a provider source name to a human-readable section label."""
    return {
        "config": "Configuration",
        "memory": "Agent Memory",
        "vault": "Knowledge Vault",
        "web": "Web Search",
    }.get(source, source.title())
