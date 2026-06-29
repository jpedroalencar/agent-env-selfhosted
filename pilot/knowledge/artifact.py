"""
KnowledgeArtifact — a structured piece of knowledge from a provider.

Minimal edition: source + content. Grows with the KnowledgeProvider framework.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class KnowledgeArtifact:
    """A piece of knowledge retrieved by a provider.

    Supports progressive loading: heavy ``content`` may be omitted until the
    ``ContextSelector`` decides the artifact should be materialised.
    """

    # Basic identification
    source: str                     # e.g. "config", "vault", "memory"
    # Optional lightweight content – may be None if not loaded
    content: Optional[str] = None   # the knowledge content (may be lazy)

    # Extended metadata for progressive loading
    metadata: dict | None = None    # arbitrary provider‑specific metadata
    priority: int = 0               # higher = more important (for selector ordering)
    estimated_tokens: int = 0       # token estimate for the content
    loaded: bool = False            # whether ``content`` is fully loaded
