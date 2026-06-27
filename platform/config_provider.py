"""
ConfigProvider — single source of truth for Platform configuration.

Reads Platform config files from config/ and exposes them
as read-only properties. Delegates to adapters/hermes/config.py
for Hermes operational data (providers, models, toolsets).

Usage:
    from platform import ConfigProvider

    config = ConfigProvider()
    routing = config.routing        # intent -> RoutingRule
    intent = routing["research"]     # {"profile": "research-analyst",
                                     #  "skills": [],
                                     #  "memory_tier": "persistent",
                                     #  "knowledge_providers": ["vault", "web"]}
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional

import yaml


# ---------------------------------------------------------------------------
# Data types
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class RoutingRule:
    """A single routing entry: intent -> execution parameters."""

    profile: str
    skills: List[str] = field(default_factory=list)
    memory_tier: str = "working"  # persistent | working | none
    knowledge_providers: List[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# ConfigProvider
# ---------------------------------------------------------------------------


class ConfigProvider:
    """Read-only access to Platform configuration.

    Loads config files from the repository's config/ directory.
    Files are loaded once on first access and cached.

    Future config files:
        config/memory-policies.yaml      — per-intent memory tier policies
        config/knowledge-providers.yaml  — provider registration and priority
    """

    def __init__(self, config_dir: Optional[str] = None):
        """
        Args:
            config_dir: Path to the config/ directory.
                        Defaults to <repo_root>/config/.
        """
        if config_dir is None:
            repo_root = Path(__file__).resolve().parent.parent
            config_dir = str(repo_root / "config")

        self._config_dir = Path(config_dir)
        self._routing: Optional[Dict[str, RoutingRule]] = None

    # -- Routing -----------------------------------------------------------

    @property
    def routing(self) -> Dict[str, RoutingRule]:
        """Intent -> RoutingRule mapping loaded from config/routing.yaml."""
        if self._routing is None:
            self._routing = self._load_routing()
        return self._routing

    def _load_routing(self) -> Dict[str, RoutingRule]:
        path = self._config_dir / "routing.yaml"
        if not path.exists():
            raise FileNotFoundError(f"Routing config not found: {path}")

        raw = yaml.safe_load(path.read_text()) or {}

        routing: Dict[str, RoutingRule] = {}
        for intent, entry in raw.get("routing", {}).items():
            routing[intent] = RoutingRule(
                profile=entry.get("profile", "orchestrator"),
                skills=entry.get("skills", []),
                memory_tier=entry.get("memory_tier", "working"),
                knowledge_providers=entry.get("knowledge_providers", []),
            )

        return routing

    # -- Lookup helpers ----------------------------------------------------

    def lookup(self, intent: str) -> Optional[RoutingRule]:
        """Return the RoutingRule for an intent, or None if unknown."""
        return self.routing.get(intent)

    def profile_for(self, intent: str) -> str:
        """Return the profile name for an intent.
        Falls back to 'orchestrator' if the intent is unknown.
        """
        rule = self.lookup(intent)
        return rule.profile if rule else "orchestrator"

    def skills_for(self, intent: str) -> List[str]:
        """Return the default skills for an intent."""
        rule = self.lookup(intent)
        return rule.skills if rule else []

    def memory_tier_for(self, intent: str) -> str:
        """Return the memory tier for an intent."""
        rule = self.lookup(intent)
        return rule.memory_tier if rule else "none"

    def knowledge_providers_for(self, intent: str) -> List[str]:
        """Return the knowledge providers for an intent, in priority order."""
        rule = self.lookup(intent)
        return rule.knowledge_providers if rule else []

    # -- Introspection -----------------------------------------------------

    @property
    def known_intents(self) -> List[str]:
        """Return all known intent names."""
        return list(self.routing.keys())

    @property
    def known_profiles(self) -> List[str]:
        """Return all known profile names, deduplicated."""
        return sorted(set(r.profile for r in self.routing.values()))

    def __repr__(self) -> str:
        return (
            f"ConfigProvider(config_dir={self._config_dir!r}, "
            f"intents={len(self.known_intents)}, "
            f"profiles={len(self.known_profiles)})"
        )
