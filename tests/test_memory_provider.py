"""Tests for deterministic MemoryProvider selection."""

from __future__ import annotations

from pathlib import Path

from pilot.knowledge.artifact import KnowledgeArtifact
from pilot.knowledge.providers.memory import MemoryProvider


def _write_memory(home: Path) -> None:
    memories = home / "memories"
    memories.mkdir(parents=True)
    (memories / "MEMORY.md").write_text(
        "Research preference: user tracks large-cap tech including AAPL and Apple earnings.\n"
        "§\n"
        "Dev preference: user wants exact diffs and pytest verification for code work.\n"
        "§\n"
        "Operations note: LXD snapshots are host-only backups.\n"
    )
    (memories / "USER.md").write_text(
        "Interest: large-cap tech financial analysis and AAPL valuation.\n"
        "§\n"
        "Style: concise answers when context is sufficient.\n"
    )


def test_relevant_memory_selection(tmp_path):
    _write_memory(tmp_path)
    provider = MemoryProvider(hermes_home=str(tmp_path))

    artifact = provider.produce_artifact("research Apple earnings valuation")

    assert isinstance(artifact, KnowledgeArtifact)
    assert artifact.source == "memory"
    assert "AAPL" in artifact.content
    assert "Apple earnings" in artifact.content
    assert "LXD snapshots" not in artifact.content


def test_irrelevant_memories_excluded(tmp_path):
    _write_memory(tmp_path)
    provider = MemoryProvider(hermes_home=str(tmp_path))

    artifact = provider.produce_artifact("operations backup snapshots")

    assert "LXD snapshots" in artifact.content
    assert "Apple earnings" not in artifact.content
    assert "pytest verification" not in artifact.content


def test_memory_selection_is_deterministic(tmp_path):
    _write_memory(tmp_path)
    provider = MemoryProvider(hermes_home=str(tmp_path))

    outputs = [provider.produce_artifact("research Apple earnings valuation").content for _ in range(5)]

    assert all(output == outputs[0] for output in outputs)


def test_memory_provider_contract_unchanged(tmp_path):
    _write_memory(tmp_path)
    provider = MemoryProvider(hermes_home=str(tmp_path))

    artifact = provider.produce_artifact("research Apple earnings valuation")

    assert set(vars(artifact)) == {"source", "content"}
