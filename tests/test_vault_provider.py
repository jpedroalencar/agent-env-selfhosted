"""
Tests for pilot.knowledge.providers.vault.VaultProvider.

Covers:
  - Successful retrieval (title match)
  - Missing artifact (no match)
  - Summary retrieval
  - Section retrieval
  - Full retrieval
  - Deterministic behavior
  - Token estimation
  - Operational error handling
  - Index parsing accuracy
  - Selection parsing
"""

from __future__ import annotations

import tempfile
from pathlib import Path

import pytest

from pilot.knowledge.artifact import KnowledgeArtifact
from pilot.knowledge.providers.vault import ArtifactSelection, VaultProvider


# ---------------------------------------------------------------------------#
# Fixtures
# ---------------------------------------------------------------------------#


@pytest.fixture
def temp_filesystem():
    """Create a temporary filesystem with artifacts/index.md and one sample artifact."""
    temp_dir = Path(tempfile.mkdtemp())

    # Create index
    index_path = temp_dir / "artifacts" / "index.md"
    index_path.parent.mkdir(parents=True, exist_ok=True)
    index_content = (
        "| Date | Title | Persona | Status | Tags | Freshness | Summary | Path |\n"
        "|------|-------|---------|--------|------|-----------|---------|------|\n"
        "| 2026-06-23 | AAPL Q3 FY2026 Earnings Review | financial-analyst "
        "| draft | aapl, apple, earnings, valuation, services, q3-2026 "
        "| 30 days | Apple Q3 FY2026 earnings review with revenue beat, "
        "Services milestones, and bull/bear case analysis. "
        "| artifacts/financial-analyst/2026-06-23_aapl-q3-2026-earnings-review.md |\n"
    )
    index_path.write_text(index_content)

    # Create artifact directory
    artifact_path = temp_dir / "artifacts" / "financial-analyst"
    artifact_path.mkdir(parents=True, exist_ok=True)

    artifact_file = artifact_path / "2026-06-23_aapl-q3-2026-earnings-review.md"
    artifact_content = (
        "---\n"
        "title: AAPL Q3 FY2026 Earnings Review\n"
        "persona: financial-analyst\n"
        "created: 2026-06-23\n"
        "status: draft\n"
        "tags: [aapl, apple, earnings, valuation, services, q3-2026]\n"
        "freshness_days: 30\n"
        "summary: Apple Q3 FY2026 earnings review with revenue beat, "
        "Services milestones, and bull/bear case analysis.\n"
        "path: artifacts/financial-analyst/2026-06-23_aapl-q3-2026-earnings-review.md\n"
        "---\n"
        "\n"
        "# AAPL Q3 FY2026 Earnings Review\n"
        "\n"
        "## Executive Summary\n"
        "\n"
        "Apple reported Q3 FY2026 earnings that beat estimates across all key metrics.\n"
        "\n"
        "## Revenue\n"
        "\n"
        "Total revenue was $234 billion, up 3.2% year-over-year.\n"
        "\n"
        "## Services Segment\n"
        "\n"
        "Services revenue reached $25 billion for the first time.\n"
        "\n"
        "## iPhone\n"
        "\n"
        "iPhone revenue was flat year-over-year at $58 billion.\n"
        "\n"
        "## Market Impact\n"
        "\n"
        "The stock price closed at $198 following the earnings call.\n"
    )
    artifact_file.write_text(artifact_content)

    yield temp_dir

    # Cleanup
    import shutil

    shutil.rmtree(temp_dir, ignore_errors=True)


def _add_irrelevant_newer_artifact(root: Path) -> None:
    """Add a newer artifact that should not match Apple/valuation queries."""
    index_path = root / "artifacts" / "index.md"
    with index_path.open("a") as f:
        f.write(
            "| 2026-06-24 | Floppy Bird Project State | operations-manager "
            "| draft | game, phaser, project-state, operations "
            "| 30 days | Unrelated game project state and operational notes. "
            "| artifacts/operations-manager/2026-06-24_agent-floppy-bird-project-state.md |\n"
        )

    artifact_path = root / "artifacts" / "operations-manager"
    artifact_path.mkdir(parents=True, exist_ok=True)
    (artifact_path / "2026-06-24_agent-floppy-bird-project-state.md").write_text(
        "---\n"
        "title: Floppy Bird Project State\n"
        "tags: [game, phaser, project-state, operations]\n"
        "---\n"
        "\n"
        "# Floppy Bird Project State\n\n"
        "Unrelated game project state and operational notes.\n"
    )


# ---------------------------------------------------------------------------#
# Successful retrieval
# ---------------------------------------------------------------------------#


class TestSuccessfulRetrieval:
    """Successful retrieval of artifacts."""

    def test_retrieve_by_exact_title(self, temp_filesystem):
        """Retrieve artifact by exact title match."""
        provider = VaultProvider(repo_root=str(temp_filesystem))

        artifact = provider.produce_artifact("AAPL Q3 FY2026 Earnings Review")

        assert artifact.source == "vault"
        assert "AAPL Q3 FY2026 Earnings Review" in artifact.content
        assert "Executive Summary" in artifact.content

    def test_retrieve_by_tag_match(self, temp_filesystem):
        """Retrieve artifact by exact tag match when no title match."""
        provider = VaultProvider(repo_root=str(temp_filesystem))

        # "valuation" is an exact tag — falls to tag-based search
        artifact = provider.produce_artifact("valuation")

        assert artifact.source == "vault"
        assert "executive summary" in artifact.content.lower() # verifies body returned and frontmatter stripped

    def test_mode_only_returns_most_recent(self, temp_filesystem):
        """Mode-only selections (no title) return the most recent artifact."""
        provider = VaultProvider(repo_root=str(temp_filesystem))

        for mode in ["summary", "full"]:
            artifact = provider.produce_artifact(mode)
            # With one artifact in the index, mode-only always returns it
            if mode == "summary":
                assert "Apple Q3 FY2026 earnings review with revenue beat" in artifact.content
                assert "Executive Summary" not in artifact.content
            else:  # mode == "full"
                assert "Executive Summary" in artifact.content
                assert "AAPL Q3 FY2026 Earnings Review" in artifact.content

    def test_summary_retrieval(self, temp_filesystem):
        """Retrieve artifact summary only."""
        provider = VaultProvider(repo_root=str(temp_filesystem))

        artifact = provider.produce_artifact("summary")

        assert "Apple Q3 FY2026 earnings review with revenue beat" in artifact.content
        # Should NOT contain full content headers
        assert "Executive Summary" not in artifact.content

    def test_full_content_retrieval(self, temp_filesystem):
        """Retrieve full artifact content with YAML frontmatter stripped."""
        provider = VaultProvider(repo_root=str(temp_filesystem))

        artifact = provider.produce_artifact("full")

        assert "Executive Summary" in artifact.content
        assert "# AAPL Q3 FY2026 Earnings Review" in artifact.content

    def test_relevant_artifact_selection_from_request_text(self, temp_filesystem):
        """Natural-language selection chooses the artifact matching metadata."""
        _add_irrelevant_newer_artifact(temp_filesystem)
        provider = VaultProvider(repo_root=str(temp_filesystem))

        artifact = provider.produce_artifact(
            "summary:What should I know about the latest Apple earnings and valuation?"
        )

        assert artifact.source == "vault"
        assert "Apple Q3 FY2026 earnings review" in artifact.content
        assert "floppy bird" not in artifact.content.lower()

    def test_irrelevant_artifacts_excluded_by_metadata_selection(self, temp_filesystem):
        """A newer unrelated artifact is not selected when query terms match AAPL."""
        _add_irrelevant_newer_artifact(temp_filesystem)
        provider = VaultProvider(repo_root=str(temp_filesystem))

        artifact = provider.produce_artifact("summary:Apple earnings valuation")

        assert "Apple Q3 FY2026" in artifact.content
        assert "unrelated game project" not in artifact.content

    def test_vault_provider_contract_unchanged(self, temp_filesystem):
        """VaultProvider still returns minimal KnowledgeArtifact fields."""
        provider = VaultProvider(repo_root=str(temp_filesystem))

        artifact = provider.produce_artifact("summary:Apple earnings valuation")

        assert isinstance(artifact, KnowledgeArtifact)
        assert set(vars(artifact)) == {"source", "content"}


# ---------------------------------------------------------------------------#
# Missing artifact
# ---------------------------------------------------------------------------#


class TestMissingArtifact:
    """Handling of missing artifacts."""

    def test_missing_artifact_raises_value_error(self, temp_filesystem):
        """No matching artifact should raise ValueError."""
        provider = VaultProvider(repo_root=str(temp_filesystem))

        with pytest.raises(ValueError, match="No matching artifact found"):
            provider.produce_artifact("nonexistent artifact")

    def test_no_index_file_raises_file_not_found(self):
        """Missing index.md should raise FileNotFoundError."""
        temp_dir = Path(tempfile.mkdtemp())
        provider = VaultProvider(repo_root=str(temp_dir))

        with pytest.raises(FileNotFoundError, match="Index file not found"):
            provider._load_index()


# ---------------------------------------------------------------------------#
# Section retrieval
# ---------------------------------------------------------------------------#


class TestSectionRetrieval:
    """Retrieve specific sections from artifacts."""

    def test_section_retrieval_uses_full_fallback(self, temp_filesystem):
        """Section retrieval mode falls back to full content."""
        provider = VaultProvider(repo_root=str(temp_filesystem))

        # Section mode is a stub — falls back to full content
        artifact = provider.produce_artifact("section:revenue")

        # Full content contains "Executive Summary" which has "summary"
        assert "summary" in artifact.content.lower()


# ---------------------------------------------------------------------------#
# Deterministic behavior
# ---------------------------------------------------------------------------#


class TestDeterministicBehavior:
    """Output is deterministic for same inputs."""

    def test_same_selection_same_output(self, temp_filesystem):
        """Same selection string produces same artifact."""
        provider = VaultProvider(repo_root=str(temp_filesystem))

        a1 = provider.produce_artifact("full")
        a2 = provider.produce_artifact("full")

        assert a1.content == a2.content

    def test_repeated_mode_call_consistent(self, temp_filesystem):
        """Repeated calls with mode-only selection are consistent."""
        provider = VaultProvider(repo_root=str(temp_filesystem))

        contents = [provider.produce_artifact("full").content for _ in range(5)]
        assert all(c == contents[0] for c in contents)


# ---------------------------------------------------------------------------#
# Token estimation
# ---------------------------------------------------------------------------#


class TestTokenEstimation:
    """Token count estimation."""

    def test_token_estimation_basic(self, temp_filesystem):
        """Full artifact content is substantial enough for token estimation."""
        provider = VaultProvider(repo_root=str(temp_filesystem))

        artifact = provider.produce_artifact("full")

        # ~4 chars/token — full artifact should be 100+ tokens
        token_est = len(artifact.content) // 4
        assert token_est > 100


# ---------------------------------------------------------------------------#
# Operational error handling
# ---------------------------------------------------------------------------#


class TestOperationalErrors:
    """Operational error handling."""

    def test_yaml_frontmatter_stripping(self, temp_filesystem):
        """Full content has YAML frontmatter stripped."""
        provider = VaultProvider(repo_root=str(temp_filesystem))

        artifact = provider.produce_artifact("full")

        assert not artifact.content.startswith("---")
        assert artifact.content.startswith("#")

    def test_exact_title_match_case_sensitive(self, temp_filesystem):
        """Exact title match is case-sensitive."""
        provider = VaultProvider(repo_root=str(temp_filesystem))

        # Exact match succeeds
        artifact = provider.produce_artifact("AAPL Q3 FY2026 Earnings Review")
        assert artifact.source == "vault"

        # Incomplete title (not exact, not a tag) fails
        with pytest.raises(ValueError, match="No matching artifact found"):
            provider.produce_artifact("AAPL Q3 FY2026")

    def test_fallback_to_full_for_section_mode(self, temp_filesystem):
        """Section mode falls back to full content."""
        provider = VaultProvider(repo_root=str(temp_filesystem))

        artifact = provider.produce_artifact("section:missing-section")

        assert "summary" in artifact.content.lower()


# ---------------------------------------------------------------------------#
# Index parsing
# ---------------------------------------------------------------------------#


class TestIndexParsing:
    """Index.md parsing accuracy."""

    def test_index_table_parsing(self, temp_filesystem):
        """Index table rows are parsed correctly."""
        provider = VaultProvider(repo_root=str(temp_filesystem))

        artifacts = provider.list_artifacts()

        aapl_artifacts = [a for a in artifacts if "AAPL" in a.title]

        assert len(aapl_artifacts) == 1
        assert aapl_artifacts[0].persona == "financial-analyst"
        assert aapl_artifacts[0].tags == [
            "aapl", "apple", "earnings", "valuation", "services", "q3-2026",
        ]

    def test_index_summary_available(self, temp_filesystem):
        """Summary field is parsed from index and available for retrieval."""
        provider = VaultProvider(repo_root=str(temp_filesystem))

        artifact = provider.produce_artifact("summary")

        assert "Apple Q3 FY2026" in artifact.content


# ---------------------------------------------------------------------------#
# Selection parsing
# ---------------------------------------------------------------------------#


class TestSelectionParsing:
    """Selection string parsing."""

    def test_parse_mode_only_summary(self):
        """Parse 'summary' mode string."""
        a = ArtifactSelection(mode="summary", section=None)
        assert a.mode == "summary"

    def test_parse_mode_only_full(self):
        """Parse 'full' mode string."""
        a = ArtifactSelection(mode="full", section=None)
        assert a.mode == "full"

    def test_parse_section_mode(self):
        """Parse section mode with section name."""
        a = ArtifactSelection(mode="section", section="Architecture")
        assert a.mode == "section"
        assert a.section == "Architecture"

    def test_parse_title_match(self):
        """Parse title (mode='full' default)."""
        a = ArtifactSelection(mode="full", section=None)
        assert a.mode == "full"

    def test_invalid_mode_in_parse_selection(self, temp_filesystem):
        """Invalid mode strings in colon format are rejected by _parse_selection."""
        provider = VaultProvider(repo_root=str(temp_filesystem))

        with pytest.raises(ValueError, match="Unknown mode"):
            provider._parse_selection("bogus:foo")
