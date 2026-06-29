"""
VaultProvider — resolves knowledge artifacts from the Knowledge Vault.

Implements the KnowledgeProvider contract: produce_artifact(intent) -> KnowledgeArtifact.
No abstractions. No registry. No caching.
Shortcut: resolves by artifact title from index.md.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING


_STOPWORDS = frozenset({
    "a", "about", "after", "all", "am", "an", "and", "are", "as", "at",
    "be", "by", "can", "could", "do", "does", "for", "from", "how", "i",
    "in", "is", "it", "know", "latest", "me", "of", "on", "or", "should",
    "tell", "the", "this", "to", "what", "when", "where", "who", "why", "with",
})

if TYPE_CHECKING:
    from pilot.knowledge.artifact import KnowledgeArtifact
from pilot.knowledge.artifact import KnowledgeArtifact


# ---------------------------------------------------------------------------#
# Data types
# ---------------------------------------------------------------------------#


@dataclass(frozen=True)
class ArtifactMetadata:
    """Metadata for a single Knowledge Vault artifact."""

    title: str
    persona: str
    created_date: str  # YYYY-MM-DD
    status: str  # draft | verified
    tags: list[str] = field(default_factory=list)
    freshness_days: int = 30
    summary: str = ""
    path: str = ""


@dataclass(frozen=True)
class ArtifactSelection:
    """Selection criteria for artifact retrieval."""

    mode: str  # summary | section | full
    title: str | None = None  # Title for exact match (None for mode-only)
    section: str | None = None  # Section title for mode='section'


# ---------------------------------------------------------------------------#
# VaultProvider
# ---------------------------------------------------------------------------#


class VaultProvider:
    """KnowledgeProvider for the Knowledge Vault filesystem layer.

    Resolves artifacts by title, tag, or persona. Supports summary, section, and
    full retrieval modes. Estimates token counts for plan capacity.

    Token estimation: ~4 characters/token for English text.
    Deterministic behavior: same (mode, section, path) -> same content.
    """

    def __init__(self, repo_root: str | None = None):
        """
        Initialize VaultProvider with repository root path.

        Args:
            repo_root: Path to repository root. Defaults to current working directory.
        """
        if repo_root is None:
            # Default to repository root so the live Gateway can read ./artifacts/index.md.
            repo_root = str(Path(__file__).resolve().parents[3])

        self._repo_root = Path(repo_root)
        self._index_path = self._repo_root / "artifacts" / "index.md"

    # -----------------------------------------------------------------------#
    # Core KnowledgeProvider contract
    # -----------------------------------------------------------------------#

    def produce_artifact(self, selection: str) -> KnowledgeArtifact:
        """
        Produce a KnowledgeArtifact from the Knowledge Vault.

        Parses the selection string into mode and section, resolves artifacts
        from the index, and returns the requested content with token estimation.

        Selection format: "<mode>[:<section>]" or "<artifact_title>"
        Examples:
            - "summary" -> return first artifact's summary
            - "section:architecture" -> return first artifact's "Architecture" section
            - "full" -> return first artifact's full content
            - "some-title" -> return artifact matching title

        Args:
            selection: Selection criteria as string. Either:
                      - Mode-only: "summary" | "section:<section_name>" | "full"
                      - Title match: exact artifact title from index.md

        Returns:
            KnowledgeArtifact with source='vault', content, and estimated tokens.

        Raises:
            FileNotFoundError: Index file does not exist.
            ValueError: Invalid selection format or no matching artifacts found.
        """
        # Parse selection string
        parsed = self._parse_selection(selection)

        # Load index
        artifacts_map = self._load_index()

        # Find matching artifact. Natural-language scoring is enabled only for
        # mode-prefixed selections such as "summary:<request>"; unprefixed
        # selections preserve legacy exact-title / exact-tag behavior.
        allow_query = ":" in selection and parsed.title is not None
        matching_artifacts = self._find_matches(parsed.title, artifacts_map, allow_query=allow_query)

        if not matching_artifacts:
            raise ValueError(f"No matching artifact found for selection: {selection}")

        # Select appropriate artifact by mode (no redundant title filter)
        selected_artifact = self._select_artifact_by_mode(
            matching_artifacts, parsed.mode, parsed.section
        )

        # Resolve content based on mode
        content = self._resolve_content(selected_artifact, parsed.mode, parsed.section)

        return KnowledgeArtifact(
            source="vault",
            content=content,
        )

    def _parse_selection(self, selection: str) -> ArtifactSelection:
        """Parse selection string into ArtifactSelection."""
        selection_str = selection.strip()

        # Mode-only: "summary" | "full"
        if selection_str in ("summary", "full"):
            return ArtifactSelection(mode=selection_str, title=None, section=None)

        # Colon-delimited: "section:<name>", "summary:<query>", "full:<query>",
        # or invalid "bogus:<something>".
        if ":" in selection_str:
            mode, rest = selection_str.split(":", 1)
            mode = mode.lower()
            rest = rest.strip() or None
            if mode in ("summary", "full"):
                return ArtifactSelection(mode=mode, title=rest, section=None)
            if mode == "section":
                return ArtifactSelection(mode="section", title=None, section=rest)
            raise ValueError(f"Unknown mode: {mode}")

        # Fallback: treat as title match
        return ArtifactSelection(mode="full", title=selection_str, section=None)

    def _load_index(self) -> dict[str, ArtifactMetadata]:
        """Load artifacts/index.md and parse metadata into a dict.

        Returns:
            Mapping from artifact title to ArtifactMetadata.

        Raises:
            FileNotFoundError: Index file does not exist.
        """
        if not self._index_path.exists():
            raise FileNotFoundError(f"Index file not found: {self._index_path}")

        index_content = self._index_path.read_text()

        # Extract index table rows
        table_pattern = r"\|[^|]+\|[^|]+\|[^|]+\|[^|]+\|[^|]+\|[^|]+\|[^|]+\|[^|]+\|"
        table_rows = re.findall(table_pattern, index_content)

        artifacts_map: dict[str, ArtifactMetadata] = {}

        # Parse each row (skip header)
        for row in table_rows[1:]:
            cells = [cell.strip() for cell in row.split("|") if cell.strip()]

            # Expected format: Date | Title | Persona | Status | Tags | Freshness | Summary | Path
            if len(cells) < 8:
                continue

            date_str, title, persona, status, tags_str, freshness_str, summary, path = (
                cells[0],
                cells[1],
                cells[2],
                cells[3],
                cells[4],
                cells[5],
                cells[6][:100],
                cells[7],
            )

            # Parse tags
            tags = [tag.strip() for tag in tags_str.split(",") if tag.strip()]

            # Parse freshness_days
            try:
                freshness_days = int(freshness_str)
            except ValueError:
                freshness_days = 30  # Default

            metadata = ArtifactMetadata(
                title=title,
                persona=persona,
                created_date=date_str,
                status=status,
                tags=tags,
                freshness_days=freshness_days,
                summary=summary,
                path=path,
            )

            artifacts_map[title] = metadata

        return artifacts_map

    def _find_matches(
        self,
        title: str | None,
        artifacts_map: dict[str, ArtifactMetadata],
        allow_query: bool = False,
    ) -> list[ArtifactMetadata]:
        """Find artifacts matching title, tag, or deterministic metadata terms.

        When title is None (mode-only selection), returns all artifacts.
        Natural-language selections are matched against title, tags, persona,
        summary, and path using deterministic lexical scoring.
        """
        # Mode-only selection: preserve existing behavior.
        if title is None:
            matches = list(artifacts_map.values())
            matches.sort(key=lambda m: m.created_date, reverse=True)
            return matches

        # Exact title match preserves existing contract behavior.
        if title in artifacts_map:
            return [artifacts_map[title]]

        query = title.strip().lower()

        # Exact tag match preserves existing contract behavior.
        exact_tag_matches = [
            meta
            for meta in artifacts_map.values()
            if any(tag.lower() == query for tag in meta.tags)
        ]
        if exact_tag_matches:
            exact_tag_matches.sort(key=lambda m: m.created_date, reverse=True)
            return exact_tag_matches

        if not allow_query:
            return []

        terms = self._query_terms(query)
        if not terms:
            return []

        scored: list[tuple[int, int, str, ArtifactMetadata]] = []
        for meta in artifacts_map.values():
            score = self._metadata_score(meta, terms)
            if score > 0:
                # Sort score descending, then newest first, then title for stable ties.
                date_key = int(meta.created_date.replace("-", "")) if meta.created_date else 0
                scored.append((-score, -date_key, meta.title.lower(), meta))

        scored.sort(key=lambda item: (item[0], item[1], item[2]))
        return [meta for _, _, _, meta in scored]

    def _query_terms(self, text: str) -> list[str]:
        """Extract deterministic lexical query terms from selection text."""
        terms = []
        for term in re.findall(r"[a-z0-9][a-z0-9.+_-]*", text.lower()):
            if len(term) < 3 or term in _STOPWORDS:
                continue
            terms.append(term)
        return list(dict.fromkeys(terms))

    def _metadata_score(self, meta: ArtifactMetadata, terms: list[str]) -> int:
        """Score artifact metadata against query terms without semantic ranking."""
        title = meta.title.lower()
        tags = [tag.lower() for tag in meta.tags]
        persona = meta.persona.lower()
        summary = meta.summary.lower()
        path = meta.path.lower()

        score = 0
        for term in terms:
            if term in tags:
                score += 6
            if term in title:
                score += 4
            if term in summary:
                score += 2
            if term in persona or term in path:
                score += 1
        return score

    def _select_artifact_by_mode(
        self,
        artifacts: list[ArtifactMetadata],
        mode: str,
        section: str | None,
    ) -> ArtifactMetadata:
        """Select an artifact based on retrieval mode.

        Args:
            artifacts: List of matching artifacts, sorted by date (newest first).
            mode: One of "summary" | "section" | "full".
            section: Section title for mode="section".

        Returns:
            The selected ArtifactMetadata.

        Raises:
            ValueError: Invalid mode or no artifacts available.
        """
        if not artifacts:
            raise ValueError("No artifacts available")

        selected = artifacts[0]

        if mode == "full":
            return selected

        if mode == "summary":
            if not selected.summary:
                raise ValueError(f"No summary available for artifact: {selected.title}")
            return selected

        if mode == "section":
            # Stub: section mode returns summary, fallback to full
            if selected.summary:
                return selected
            return selected

        raise ValueError(f"Unknown mode: {mode}")

    def _resolve_content(
        self,
        artifact: ArtifactMetadata,
        mode: str,
        section: str | None,
    ) -> str:
        """Resolve content based on retrieval mode.

        Args:
            artifact: Artifact metadata.
            mode: One of "summary" | "section" | "full".
            section: Section title for mode="section".

        Returns:
            Resolved artifact content.
        """
        if mode == "summary":
            if not artifact.summary:
                return f"No summary available for artifact: {artifact.title}"
            return artifact.summary

        if mode == "full":
            artifact_path = self._repo_root / artifact.path
            if not artifact_path.exists():
                return f"Artifact file not found: {artifact.path}"

            content = artifact_path.read_text()
            # Handle YAML frontmatter
            if content.startswith("---"):
                # Remove YAML frontmatter. Use DOTALL to allow newlines in the block
                # and MULTILINE so ^ matches the start of a line for the closing '---'.
                content = re.sub(r"^---\n.*?^---\n", "", content, flags=re.DOTALL | re.MULTILINE)

            return content.strip()

        # Section and unknown modes: fall back to full
        return self._resolve_content(artifact, "full", None)

    def _estimate_tokens(self, content: str) -> int:
        """Estimate token count for a string.

        Uses a conservative estimate of 4 characters/token for English text.

        Args:
            content: Text content.

        Returns:
            Estimated token count.
        """
        return len(content) // 4

    # -----------------------------------------------------------------------#
    # Introspection
    # -----------------------------------------------------------------------#

    def list_artifacts(self) -> list[ArtifactMetadata]:
        """List all indexed artifacts.

        Returns:
            List of ArtifactMetadata, sorted by date (newest first).
        """
        artifacts_map = self._load_index()

        artifacts = sorted(
            artifacts_map.values(),
            key=lambda m: m.created_date,
            reverse=True,
        )

        return artifacts

    def __repr__(self) -> str:
        return f"VaultProvider(repo_root={self._repo_root!r})"
