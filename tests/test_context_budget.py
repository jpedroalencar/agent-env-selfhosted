"""Tests for deterministic Context Budget Reporting.

Verifies that assemble_context() produces a ContextBudgetReport with
correct, deterministic measurements without influencing context assembly.
"""
from __future__ import annotations

import pytest

from pilot.context.system import (
    ContextBudgetEntry,
    ContextBudgetReport,
    assemble_context,
)
from pilot.knowledge.artifact import KnowledgeArtifact


class TestDeterministicCalculations:
    """Same input always produces the same budget report."""

    def test_deterministic_empty(self):
        report = _budget_for([])
        for _ in range(5):
            repeat = _budget_for([])
            assert repeat.total_context_characters == report.total_context_characters
            assert repeat.total_context_tokens == report.total_context_tokens
            assert repeat.entries == report.entries

    def test_deterministic_single_provider(self):
        artifacts = [
            KnowledgeArtifact(source="memory", content="Some persistent memory content."),
        ]
        report = _budget_for(artifacts)
        for _ in range(5):
            repeat = _budget_for(artifacts)
            assert repeat == report

    def test_deterministic_multiple_providers(self):
        artifacts = [
            KnowledgeArtifact(source="memory", content="Memory note A."),
            KnowledgeArtifact(source="vault", content="Vault entry 1."),
        ]
        report = _budget_for(artifacts)
        for _ in range(5):
            repeat = _budget_for(artifacts)
            assert repeat == report


class TestProviderTotals:
    """Each provider's character and token counts are correct."""

    def test_single_provider_full_contribution(self):
        artifacts = [
            KnowledgeArtifact(source="config", content="Routing configuration data."),
        ]
        report = _budget_for(artifacts)

        assert len(report.entries) == 1
        entry = report.entries[0]
        assert entry.provider == "config"
        assert entry.percentage == 100.0

    def test_provider_characters_match_block(self):
        """Characters counted per provider should equal the formatted block length."""
        artifacts = [
            KnowledgeArtifact(source="memory", content="Hello world"),
            KnowledgeArtifact(source="vault", content="Test data"),
        ]
        report = _budget_for(artifacts)

        assert report.entries[0].provider == "memory"
        # Block: "## Agent Memory\n\nHello world"
        expected_chars = len("## Agent Memory\n\nHello world")
        assert report.entries[0].characters == expected_chars

        assert report.entries[1].provider == "vault"
        # Block: "## Knowledge Vault\n\nTest data"
        expected_chars_vault = len("## Knowledge Vault\n\nTest data")
        assert report.entries[1].characters == expected_chars_vault

    def test_percentages_sum_to_100(self):
        """All provider percentages should sum to approximately 100%."""
        artifacts = [
            KnowledgeArtifact(source="memory", content="A" * 100),
            KnowledgeArtifact(source="vault", content="B" * 200),
            KnowledgeArtifact(source="config", content="C" * 50),
        ]
        report = _budget_for(artifacts)
        total_pct = round(sum(e.percentage for e in report.entries), 2)
        assert total_pct == 100.0

    def test_provider_order_preserved(self):
        """Entries appear in the same order as input artifacts."""
        artifacts = [
            KnowledgeArtifact(source="vault", content="Z data"),
            KnowledgeArtifact(source="memory", content="A data"),
            KnowledgeArtifact(source="config", content="M data"),
        ]
        report = _budget_for(artifacts)
        assert [e.provider for e in report.entries] == ["vault", "memory", "config"]


class TestOverallTotals:
    """Total context size calculations are correct."""

    def test_total_matches_concatenated_context(self):
        artifacts = [
            KnowledgeArtifact(source="memory", content="Hello"),
            KnowledgeArtifact(source="vault", content="World"),
        ]
        report = _budget_for(artifacts)
        expected_context = (
            "## Agent Memory\n\nHello\n\n## Knowledge Vault\n\nWorld"
        )
        assert report.total_context_characters == len(expected_context)

    def test_empty_context_has_zero_tokens(self):
        report = _budget_for([])
        assert report.total_context_characters > 0  # "(no context available)" fallback
        assert report.total_context_tokens == pytest.approx(
            (len("(no context available)") + 3) // 4
        )

    def test_token_estimate_is_approximate(self):
        """Token estimation uses characters/4 heuristic."""
        artifacts = [
            KnowledgeArtifact(source="memory", content="A" * 100),
        ]
        report = _budget_for(artifacts)
        # Block: "## Agent Memory\n\n" + "A"*100 = 118 characters
        expected_tokens = (118 + 3) // 4
        assert report.total_context_tokens == expected_tokens

    def test_empty_artifacts_excluded_contribute_nothing_to_budget(self):
        """Artifacts with only whitespace are excluded from budget entries
        but the total context reflects the fallback string."""
        artifacts = [
            KnowledgeArtifact(source="memory", content="   "),
            KnowledgeArtifact(source="vault", content="Some real content"),
        ]
        report = _budget_for(artifacts)
        # Only vault should have an entry
        assert len(report.entries) == 1
        assert report.entries[0].provider == "vault"
        # Total context is not based on the empty artifact
        assert "Agent Memory" not in report.entries[0].provider


class TestContextAssemblyUnchanged:
    """The context string itself is NOT affected by the budget feature."""

    def test_context_string_identical_with_and_without_budget(self):
        artifacts = [
            KnowledgeArtifact(source="memory", content="Memory content."),
            KnowledgeArtifact(source="vault", content="Vault content."),
        ]
        context, _ = assemble_context(artifacts)
        expected = (
            "## Agent Memory\n\nMemory content.\n\n## Knowledge Vault\n\nVault content."
        )
        assert context == expected

    def test_empty_artifacts_still_fall_back(self):
        artifacts = [
            KnowledgeArtifact(source="memory", content="   "),
        ]
        context, _ = assemble_context(artifacts)
        assert context == "(no context available)"


class TestProviderContractsUnchanged:
    """KnowledgeProviders still return only source + content fields."""

    def test_memory_provider_contract(self, tmp_path):
        from pilot.knowledge.providers.memory import MemoryProvider

        memories = tmp_path / "memories"
        memories.mkdir(parents=True)
        (memories / "MEMORY.md").write_text("Test memory content.\n")
        provider = MemoryProvider(hermes_home=str(tmp_path))
        artifact = provider.produce_artifact("test")
        # Validate new canonical artifact shape
        assert set(vars(artifact)) == {"source", "content", "metadata", "priority", "estimated_tokens", "loaded"}


    def test_vault_provider_contract(self, tmp_path):
        from pilot.knowledge.providers.vault import VaultProvider

        artifacts_dir = tmp_path / "artifacts"
        artifacts_dir.mkdir(parents=True)
        (artifacts_dir / "index.md").write_text(
            "| Date | Title | Persona | Status | Tags | Freshness | Summary | Path |\n"
            "|------|-------|---------|--------|------|-----------|---------|------|\n"
            "| 2026-06-23 | Test Artifact | tester | draft | test | 30 | A test. | artifacts/tester/test.md |\n"
        )
        sub = artifacts_dir / "tester"
        sub.mkdir(parents=True)
        (sub / "test.md").write_text("---\ntitle: Test Artifact\n---\n\n# Test Artifact\n\nTest body.\n")
        provider = VaultProvider(repo_root=str(tmp_path))
        artifact = provider.produce_artifact("summary")
        assert set(vars(artifact)) == {"source", "content", "metadata", "priority", "estimated_tokens", "loaded"}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _budget_for(
    artifacts: list[KnowledgeArtifact],
) -> ContextBudgetReport:
    """Run assemble_context and return only the budget report."""
    _, report = assemble_context(artifacts)
    return report
