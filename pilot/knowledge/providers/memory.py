"""
MemoryProvider — reads agent memory and produces KnowledgeArtifacts.

Implements the KnowledgeProvider contract: produce_artifact(intent) -> KnowledgeArtifact.
No abstractions. No registry. No caching.

Shortcut: reads MEMORY.md only. USER.md can be added later.
"""

from __future__ import annotations

import os
from pathlib import Path

from pilot.knowledge.artifact import KnowledgeArtifact


class MemoryProvider:
    """KnowledgeProvider for agent and user memory."""

    def __init__(self, hermes_home: str | None = None):
        if hermes_home is None:
            hermes_home = os.path.expanduser("~/.hermes")
        self._memories_dir = Path(hermes_home) / "memories"

    def produce_artifact(self, intent: str) -> KnowledgeArtifact:
        """Produce a KnowledgeArtifact from agent memory.

        Reads MEMORY.md and returns its content as a single artifact.
        Skips empty or missing files gracefully.
        """
        memory_path = self._memories_dir / "MEMORY.md"

        if not memory_path.exists():
            return KnowledgeArtifact(
                source="memory",
                content="(no agent memory file found)",
            )

        content = memory_path.read_text().strip()

        if not content:
            return KnowledgeArtifact(
                source="memory",
                content="(agent memory is empty)",
            )

        return KnowledgeArtifact(source="memory", content=content)
