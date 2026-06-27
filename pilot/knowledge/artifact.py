"""
KnowledgeArtifact — a structured piece of knowledge from a provider.

Minimal edition: source + content. Grows with the KnowledgeProvider framework.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class KnowledgeArtifact:
    """A piece of knowledge retrieved by a provider."""

    source: str   # e.g. "config", "vault", "web"
    content: str  # the knowledge content
