"""Tests for pilot.config_provider.ConfigProvider.

Covers:
  - Deterministic behavior (same input → same output)
  - Unknown keys fall back to orchestrator
  - Repeated lookups return equivalent results
  - RoutingRule is frozen (immutable)
  - Malformed configuration raises expected errors
  - Missing file raises FileNotFoundError
  - Empty routing key returns empty dict
"""

from __future__ import annotations

import tempfile
from pathlib import Path

import pytest
import yaml

from pilot.config_provider import ConfigProvider, RoutingRule


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def temp_config_dir():
    """Create a temporary config directory with a valid routing.yaml."""
    with tempfile.TemporaryDirectory() as tmp:
        config_dir = Path(tmp) / "config"
        config_dir.mkdir()

        routing = {
            "routing": {
                "research": {
                    "profile": "research-analyst",
                    "skills": [],
                    "memory_tier": "persistent",
                    "knowledge_providers": ["vault", "web"],
                },
                "financial_analysis": {
                    "profile": "financial-analyst",
                    "skills": ["stock-bull-bear-report"],
                    "memory_tier": "persistent",
                    "knowledge_providers": ["vault", "web"],
                },
                "casual": {
                    "profile": "orchestrator",
                    "skills": [],
                    "memory_tier": "none",
                    "knowledge_providers": [],
                },
            }
        }
        (config_dir / "routing.yaml").write_text(yaml.dump(routing))
        yield str(tmp)  # return the temp root, not config/


@pytest.fixture
def config(temp_config_dir):
    return ConfigProvider(config_dir=temp_config_dir + "/config")


# ---------------------------------------------------------------------------
# Deterministic behavior
# ---------------------------------------------------------------------------


class TestDeterministic:
    """Same input always produces same output."""

    def test_same_config_same_routing(self, temp_config_dir):
        a = ConfigProvider(config_dir=temp_config_dir + "/config")
        b = ConfigProvider(config_dir=temp_config_dir + "/config")
        assert a.routing == b.routing

    def test_same_intent_same_profile(self, config):
        for _ in range(5):
            assert config.profile_for("research") == "research-analyst"

    def test_routing_keys_are_stable(self, config):
        first = list(config.routing.keys())
        second = list(config.routing.keys())
        assert first == second


# ---------------------------------------------------------------------------
# Unknown keys — fallback to orchestrator
# ---------------------------------------------------------------------------


class TestUnknownKeys:
    """Unknown intents gracefully degrade to the orchestrator profile."""

    def test_unknown_intent_returns_none_from_lookup(self, config):
        assert config.lookup("nonexistent") is None

    def test_unknown_intent_falls_back_to_orchestrator(self, config):
        assert config.profile_for("nonexistent") == "orchestrator"

    def test_unknown_intent_skills_empty(self, config):
        assert config.skills_for("nonexistent") == []

    def test_unknown_intent_memory_tier_none(self, config):
        assert config.memory_tier_for("nonexistent") == "none"

    def test_unknown_intent_providers_empty(self, config):
        assert config.knowledge_providers_for("nonexistent") == []

    def test_empty_string_falls_back(self, config):
        assert config.profile_for("") == "orchestrator"


# ---------------------------------------------------------------------------
# Repeated lookups
# ---------------------------------------------------------------------------


class TestRepeatedLookups:
    """Repeated lookups return equivalent results — cache is transparent."""

    def test_repeated_lookup_same_rule(self, config):
        r1 = config.lookup("research")
        r2 = config.lookup("research")
        assert r1 == r2

    def test_repeated_lookup_same_profile(self, config):
        p1 = config.profile_for("research")
        p2 = config.profile_for("research")
        assert p1 == p2

    def test_repeated_lookup_same_skills(self, config):
        s1 = config.skills_for("financial_analysis")
        s2 = config.skills_for("financial_analysis")
        assert s1 == s2
        assert s1 == ["stock-bull-bear-report"]


# ---------------------------------------------------------------------------
# RoutingRule invariants
# ---------------------------------------------------------------------------


class TestRoutingRuleInvariants:
    """RoutingRule is frozen — immutable after construction."""

    def test_routing_rule_is_frozen(self):
        rule = RoutingRule(profile="test", skills=[], memory_tier="working")
        with pytest.raises(Exception):
            rule.profile = "changed"  # type: ignore[misc]

    def test_default_memory_tier_is_working(self):
        rule = RoutingRule(profile="test")
        assert rule.memory_tier == "working"

    def test_default_skills_empty(self):
        rule = RoutingRule(profile="test")
        assert rule.skills == []

    def test_default_providers_empty(self):
        rule = RoutingRule(profile="test")
        assert rule.knowledge_providers == []

    def test_equality(self):
        a = RoutingRule(profile="x", skills=["a"], memory_tier="persistent")
        b = RoutingRule(profile="x", skills=["a"], memory_tier="persistent")
        assert a == b

    def test_inequality(self):
        a = RoutingRule(profile="x")
        b = RoutingRule(profile="y")
        assert a != b


# ---------------------------------------------------------------------------
# Malformed configuration
# ---------------------------------------------------------------------------


class TestMalformedConfig:
    """Malformed configuration produces expected operational errors."""

    def test_missing_config_dir(self):
        provider = ConfigProvider(config_dir="/nonexistent/path")
        with pytest.raises(FileNotFoundError):
            _ = provider.routing  # trigger lazy load

    def test_missing_routing_file(self, temp_config_dir):
        # Remove the routing.yaml we just created
        (Path(temp_config_dir) / "config" / "routing.yaml").unlink()
        provider = ConfigProvider(config_dir=temp_config_dir + "/config")
        with pytest.raises(FileNotFoundError):
            _ = provider.routing  # trigger lazy load

    def test_empty_routing_file(self, temp_config_dir):
        (Path(temp_config_dir) / "config" / "routing.yaml").write_text("")
        provider = ConfigProvider(config_dir=temp_config_dir + "/config")
        assert provider.routing == {}

    def test_routing_key_missing(self, temp_config_dir):
        (Path(temp_config_dir) / "config" / "routing.yaml").write_text(
            yaml.dump({"other_key": {}})
        )
        provider = ConfigProvider(config_dir=temp_config_dir + "/config")
        assert provider.routing == {}

    def test_invalid_yaml(self, temp_config_dir):
        (Path(temp_config_dir) / "config" / "routing.yaml").write_text(
            "{{{ broken: [yaml"
        )
        provider = ConfigProvider(config_dir=temp_config_dir + "/config")
        with pytest.raises(yaml.YAMLError):
            _ = provider.routing  # trigger lazy load

    def test_routing_entry_missing_profile(self, temp_config_dir):
        """Entry without a profile field gets 'orchestrator' default."""
        routing = {"routing": {"test": {"skills": ["a"]}}}
        (Path(temp_config_dir) / "config" / "routing.yaml").write_text(
            yaml.dump(routing)
        )
        provider = ConfigProvider(config_dir=temp_config_dir + "/config")
        assert provider.profile_for("test") == "orchestrator"

    def test_routing_entry_missing_skills(self, temp_config_dir):
        """Entry without skills field gets empty list."""
        routing = {"routing": {"test": {"profile": "dev"}}}
        (Path(temp_config_dir) / "config" / "routing.yaml").write_text(
            yaml.dump(routing)
        )
        provider = ConfigProvider(config_dir=temp_config_dir + "/config")
        assert provider.skills_for("test") == []

    def test_routing_entry_null_skills(self, temp_config_dir):
        """Entry with null skills becomes empty list."""
        routing = {"routing": {"test": {"profile": "dev", "skills": None}}}
        (Path(temp_config_dir) / "config" / "routing.yaml").write_text(
            yaml.dump(routing)
        )
        provider = ConfigProvider(config_dir=temp_config_dir + "/config")
        assert provider.skills_for("test") == []


# ---------------------------------------------------------------------------
# Known intents and profiles
# ---------------------------------------------------------------------------


class TestKnownIntents:
    """The set of known intents and profiles is correct."""

    def test_known_intents_contains_all_keys(self, config):
        assert set(config.known_intents) == {
            "research", "financial_analysis", "casual"
        }

    def test_known_profiles_deduplicated(self, config):
        assert set(config.known_profiles) == {
            "research-analyst", "financial-analyst", "orchestrator"
        }

    def test_known_profiles_sorted(self, config):
        assert config.known_profiles == sorted(config.known_profiles)


# ---------------------------------------------------------------------------
# Real config file (integration)
# ---------------------------------------------------------------------------


class TestRealConfig:
    """Verify the real routing.yaml in the repository."""

    def test_real_config_loads(self):
        config = ConfigProvider()  # Uses repo default
        assert len(config.known_intents) == 15
        assert len(config.known_profiles) == 5

    def test_real_config_all_intents_have_profile(self):
        config = ConfigProvider()
        for intent in config.known_intents:
            rule = config.lookup(intent)
            assert rule is not None, f"Intent '{intent}' has no rule"
            assert rule.profile, f"Intent '{intent}' has empty profile"

    def test_real_config_all_profiles_are_known(self):
        known = {"financial-analyst", "research-analyst", "dev", "ops-manager", "orchestrator"}
        config = ConfigProvider()
        assert set(config.known_profiles) == known
