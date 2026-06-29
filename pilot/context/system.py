"""
Context System — assembles context from KnowledgeArtifacts.

Minimal edition: accepts a list of artifacts and formats them.
No abstraction. No caching. No provider registry.

Contracts: the Context System only assembles context.
KnowledgeProviders produce artifacts. The Context System
receives them and formats them into the prompt.
"""

from __future__ import annotations

from dataclasses import dataclass

from pilot.knowledge.artifact import KnowledgeArtifact


@dataclass(frozen=True)
class ContextBudgetEntry:
    provider: str
    characters: int
    estimated_tokens: int
    percentage: float


@dataclass(frozen=True)
class ContextBudgetReport:
    entries: list[ContextBudgetEntry]
    total_context_characters: int
    total_context_tokens: int


def assemble_context(
    artifacts: list[KnowledgeArtifact],
) -> tuple[str, ContextBudgetReport]:
    """Assemble context from a list of KnowledgeArtifacts.

    Each artifact is formatted as a labeled block. Blocks are
    joined with double newlines. Empty artifacts are skipped.

    The Context System does not know or care which providers
    produced the artifacts — it only formats what it receives.
    """
    blocks: list[str] = []
    entries: list[ContextBudgetEntry] = []

    for artifact in artifacts:
        if not artifact.content.strip():
            continue

        label = _label_for(artifact.source)
        block = f"## {label}\n\n{artifact.content}"
        blocks.append(block)
        characters = len(block)
        estimated_tokens = _estimate_tokens(characters)
        entries.append(
            ContextBudgetEntry(
                provider=artifact.source,
                characters=characters,
                estimated_tokens=estimated_tokens,
                percentage=0.0,
            )
        )

    total_context = "\n\n".join(blocks) if blocks else "(no context available)"
    total_context_characters = len(total_context)
    total_context_tokens = _estimate_tokens(total_context_characters)

    if total_context_characters > 0:
        # Compute raw percentages per entry.
        raw_percentages = [
            (entry.characters / total_context_characters) * 100 for entry in entries
        ]
        # Round each to two decimals, but keep the last entry adjustable.
        rounded = [round(p, 2) for p in raw_percentages]
        if rounded:
            # Adjust last entry so total sum = 100.00 (within rounding tolerance).
            total_except_last = sum(rounded[:-1])
            rounded[-1] = round(100.0 - total_except_last, 2)
        # Recreate entries with adjusted percentages.
        entries = [
            ContextBudgetEntry(
                provider=entry.provider,
                characters=entry.characters,
                estimated_tokens=entry.estimated_tokens,
                percentage=rounded[i],
            )
            for i, entry in enumerate(entries)
        ]
        

    return total_context, ContextBudgetReport(
        entries=entries,
        total_context_characters=total_context_characters,
        total_context_tokens=total_context_tokens,
    )


def _estimate_tokens(characters: int) -> int:
    return (characters + 3) // 4


def _label_for(source: str) -> str:
    """Map a provider source name to a human-readable section label."""
    return {
        "config": "Configuration",
        "memory": "Agent Memory",
        "vault": "Knowledge Vault",
        "web": "Web Search",
    }.get(source, source.title())
