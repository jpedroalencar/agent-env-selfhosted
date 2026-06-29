"""
MemoryProvider — reads agent/user memory and produces KnowledgeArtifacts.

Implements the KnowledgeProvider contract: produce_artifact(intent) -> KnowledgeArtifact.
No abstractions. No registry. No caching.

Selection is deterministic and provider-local: the caller passes the current
intent/request text as the existing provider key, and MemoryProvider filters
memory entries using simple keyword matching.
"""

from __future__ import annotations

import os
import re
from pathlib import Path

from pilot.knowledge.artifact import KnowledgeArtifact


_STOPWORDS = frozenset({
    "a", "about", "after", "all", "am", "an", "and", "are", "as", "at",
    "be", "by", "can", "could", "do", "does", "for", "from", "how", "i",
    "in", "is", "it", "know", "latest", "me", "of", "on", "or", "should",
    "tell", "the", "this", "to", "what", "when", "where", "who", "why", "with",
})


from pilot.provider_registry import register

class MemoryProvider:
    """KnowledgeProvider for agent and user memory."""

    def __init__(self, hermes_home: str | None = None):
        if hermes_home is None:
            hermes_home = os.path.expanduser("~/.hermes")
        self._memories_dir = Path(hermes_home) / "memories"

    def produce_artifact(self, intent: str) -> KnowledgeArtifact:
        """Produce a relevant KnowledgeArtifact from memory.

        Reads MEMORY.md and USER.md when present, splits them into durable memory
        entries, and returns only entries matching the current provider key.
        The key is intentionally provider-defined; Gateway passes intent plus
        user request text without changing the KnowledgeArtifact contract.
        """
        entries = self._load_entries()

        if not entries:
            return KnowledgeArtifact(
                source="memory",
                content=None,
                loaded=False,
                estimated_tokens=0,
            )

        terms = self._query_terms(intent)
        matches = self._select_entries(entries, terms)

        if not matches:
            return KnowledgeArtifact(
                source="memory",
                content="(no relevant memory found)",
                loaded=False,
            )

        content = "\n§\n".join(matches)
        return KnowledgeArtifact(
            source="memory",
            content=content,
            loaded=True,
            estimated_tokens=len(content.split()),
        )

    def _load_entries(self) -> list[str]:
        """Load durable memory entries from MEMORY.md and USER.md."""
        entries: list[str] = []
        for filename in ("MEMORY.md", "USER.md"):
            path = self._memories_dir / filename
            if not path.exists():
                continue
            content = path.read_text().strip()
            if not content:
                continue
            for entry in re.split(r"\n§\n", content):
                entry = entry.strip()
                if entry:
                    entries.append(entry)
        return entries

    def _query_terms(self, text: str) -> list[str]:
        """Extract deterministic lexical query terms."""
        terms = []
        for term in re.findall(r"[a-z0-9][a-z0-9.+_-]*", text.lower()):
            if len(term) < 3 or term in _STOPWORDS:
                continue
            terms.append(term)

        # Preserve order while deduping.
        return list(dict.fromkeys(terms))

    def _select_entries(self, entries: list[str], terms: list[str]) -> list[str]:
        """Return matching memory entries sorted deterministically by score."""
        if not terms:
            return []

        scored: list[tuple[int, int, str]] = []
        for index, entry in enumerate(entries):
            entry_terms = set(self._query_terms(entry))
            expanded_terms = self._expand_terms(terms)
            score = sum(1 for term in expanded_terms if term in entry_terms)
            if score > 0:
                scored.append((-score, index, entry))

        scored.sort()
        return [entry for _, _, entry in scored]

    def _expand_terms(self, terms: list[str]) -> list[str]:
        """Expand deterministic lexical aliases without semantic ranking."""
        expanded = list(terms)
        if "apple" in expanded and "aapl" not in expanded:
            expanded.append("aapl")
        if "aapl" in expanded and "apple" not in expanded:
            expanded.append("apple")
        return list(dict.fromkeys(expanded))

# Register provider
register('memory', MemoryProvider)