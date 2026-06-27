"""
RequestParser — extracts structured signals from raw user text.

Pure regex + string predicates. No NLP, no embeddings, no model calls.
Produces a ``ParsedRequest`` containing classified signals that the
downstream ``RequestClassifier`` uses to determine the ``RequestShape``.

INPUT_MAX_CHARS: text longer than this is truncated before parsing.
"""

from __future__ import annotations

import re
from typing import List, Optional

from ._types import ParsedRequest

# ── Constants ────────────────────────────────────────────────────────────────

INPUT_MAX_CHARS = 10_000  # per spec: truncate input >10KB

# Words strongly suggesting a question
_QUESTION_WORDS = {
    "who", "what", "when", "where", "why", "how",
    "which", "whose", "whom", "can", "could", "would",
    "will", "shall", "should", "is", "are", "do", "does",
    "did", "has", "have", "had", "am",
}

# Words and patterns suggesting an imperative / code-change request
_IMPERATIVE_LEADING_VERBS = {
    "fix", "add", "create", "remove", "delete", "update",
    "change", "refactor", "implement", "build", "deploy",
    "install", "configure", "setup", "set", "run", "start",
    "stop", "restart", "patch", "merge", "rebase", "commit",
    "push", "pull", "clone", "test", "debug", "optimize",
    "rewrite", "replace", "rename", "move", "copy", "extract",
    "convert", "generate", "compile", "lint", "format",
    "enable", "disable", "kill", "edit", "open", "close",
    "publish", "release", "schedule", "migrate", "audit",
    "review", "check", "verify", "validate", "monitor",
    "send", "post", "write", "read", "search", "find",
}

# Terms that suggest a Hermes self-service / configuration request
_HERMES_TERMS = {
    "hermes", "hermes-agent", "hermes agent",
}

# Terms that suggest code-related content
_CODE_TERMS = {
    "code", "function", "class", "module", "import",
    "def ", "bug", "error", "exception", "traceback",
    "test", "pytest", "unittest", "lint", "type",
    "api", "endpoint", "route", "middleware",
    "authentication", "auth", "authorization", "token", "session",
    "database", "query", "sql", "schema", "migration",
    "config", "yaml", "json", "env", "variable",
    "git", "branch", "commit", "pr", "pull request",
    "docker", "container", "deploy", "ci/cd", "pipeline",
    "python", "javascript", "typescript", "rust", "go",
    "react", "node", "fastapi", "flask", "django",
}

# Regex patterns (compiled once at module load)
_URL_RE = re.compile(
    r'https?://[^\s<>"{}|\\^`\[\]]+',
    re.IGNORECASE,
)
_PATH_RE = re.compile(
    r'(?:(?:~|/|[A-Za-z]:[/\\])[\w./\\-]+(?:\.\w{1,10})\b)',
)
_COMMAND_PREFIX_RE = re.compile(r'^[/!](\w+)')

# Unicode script ranges for language detection
_CJK_RANGES = [
    (0x4E00, 0x9FFF),   # CJK Unified Ideographs
    (0x3400, 0x4DBF),   # CJK Unified Ideographs Extension A
    (0x20000, 0x2A6DF), # CJK Unified Ideographs Extension B
    (0x3040, 0x309F),   # Hiragana
    (0x30A0, 0x30FF),   # Katakana
    (0xAC00, 0xD7AF),   # Hangul Syllables
]
_CYRILLIC_RANGES = [
    (0x0400, 0x04FF),   # Cyrillic
    (0x0500, 0x052F),   # Cyrillic Supplement
]
_ARABIC_RANGES = [
    (0x0600, 0x06FF),   # Arabic
    (0x0750, 0x077F),   # Arabic Supplement
    (0xFB50, 0xFDFF),   # Arabic Presentation Forms-A
    (0xFE70, 0xFEFF),   # Arabic Presentation Forms-B
]
_DEVANAGARI_RANGES = [
    (0x0900, 0x097F),   # Devanagari
]


def _detect_script_families(text: str) -> List[str]:
    """Detect non-Latin script families in the text."""
    families: List[str] = []
    has_cjk = False
    has_cyrillic = False
    has_arabic = False
    has_devanagari = False
    has_latin = False

    for ch in text:
        cp = ord(ch)
        if cp < 128:
            has_latin = True
            continue
        if not has_cjk:
            for low, high in _CJK_RANGES:
                if low <= cp <= high:
                    has_cjk = True
                    break
        if not has_cyrillic:
            for low, high in _CYRILLIC_RANGES:
                if low <= cp <= high:
                    has_cyrillic = True
                    break
        if not has_arabic:
            for low, high in _ARABIC_RANGES:
                if low <= cp <= high:
                    has_arabic = True
                    break
        if not has_devanagari:
            for low, high in _DEVANAGARI_RANGES:
                if low <= cp <= high:
                    has_devanagari = True
                    break

    if has_cjk:
        families.append("CJK")
    if has_cyrillic:
        families.append("Cyrillic")
    if has_arabic:
        families.append("Arabic")
    if has_devanagari:
        families.append("Devanagari")
    if not families and has_latin:
        families.append("Latin")
    return families


def _extract_urls(text: str) -> List[str]:
    """Extract all URLs from text."""
    return [m.group(0).rstrip(".,;:!?") for m in _URL_RE.finditer(text)]


def _extract_file_paths(text: str) -> List[str]:
    """Extract file-path-like patterns from text."""
    return [m.group(0) for m in _PATH_RE.finditer(text)]


def _extract_command_prefix(text: str) -> Optional[str]:
    """Extract a leading /command or !command prefix."""
    stripped = text.strip()
    m = _COMMAND_PREFIX_RE.match(stripped)
    if m:
        return m.group(1)
    return None


def _has_question(text: str) -> bool:
    """Check whether the text contains question markers."""
    stripped = text.strip()
    # Direct question mark
    if "?" in stripped:
        return True
    # Leading question word
    first_word = stripped.split()[0].lower().rstrip(",:;") if stripped.split() else ""
    if first_word in _QUESTION_WORDS:
        return True
    return False


def _extract_imperative_verbs(text: str) -> List[str]:
    """Extract imperative verbs from the leading portion of text."""
    stripped = text.strip()
    if not stripped:
        return []
    first_word = stripped.split()[0].lower().rstrip(",:;.!?")
    if first_word in _IMPERATIVE_LEADING_VERBS:
        return [first_word]
    return []


def _extract_mentioned_entities(text: str) -> List[str]:
    """Extract CamelCase and snake_case entities mentioned in text."""
    # CamelCase and PascalCase — at least one uppercase letter followed by lowercase,
    # then optionally more CamelCase segments
    camel = re.findall(r'\b[A-Z][a-z]+(?:[A-Z][a-zA-Z]*)*\b', text)
    # snake_case with at least one underscore
    snake = re.findall(r'\b[a-z]+(?:_[a-z]+)+\b', text.lower())
    entities = list(dict.fromkeys(camel + snake))  # dedupe, preserve order
    return entities


def _extract_skill_mentions(text: str, available_skills: List[str]) -> List[str]:
    """Find explicit mentions of installed skill names."""
    lower = text.lower()
    mentioned = []
    for skill in available_skills:
        if skill.lower() in lower:
            mentioned.append(skill)
    return mentioned


def _contains_hermes_terms(text: str) -> bool:
    """Check if the text mentions Hermes-specific terms."""
    lower = text.lower()
    return any(term in lower for term in _HERMES_TERMS)


def _contains_code_terms(text: str) -> bool:
    """Check if the text mentions code-related terms."""
    lower = text.lower()
    count = sum(1 for term in _CODE_TERMS if term in lower)
    # Require at least 2 code terms to avoid false positives from
    # casual conversation that happens to mention a single term
    return count >= 2


def parse(user_message: str, available_skills: Optional[List[str]] = None) -> ParsedRequest:
    """Parse raw user text into structured signals.

    This is the single entry point for signal extraction.  No model
    inference, no I/O.  Pure function of (text, skills).

    Args:
        user_message: The raw, untouched user text.
        available_skills: Names of currently installed skills.

    Returns:
        A ``ParsedRequest`` with all extracted signals populated.
    """
    if available_skills is None:
        available_skills = []

    raw = user_message
    truncated = False
    if len(raw) > INPUT_MAX_CHARS:
        raw = raw[:INPUT_MAX_CHARS]
        truncated = True

    words = raw.split()
    word_count = len(words)

    urls = _extract_urls(raw)
    file_paths = _extract_file_paths(raw)
    command_prefix = _extract_command_prefix(raw)
    has_q = _has_question(raw)
    imperative_verbs = _extract_imperative_verbs(raw)
    mentioned_entities = _extract_mentioned_entities(raw)
    skill_mentions = _extract_skill_mentions(raw, available_skills)
    script_families = _detect_script_families(raw)

    return ParsedRequest(
        raw_text=raw,
        explicit_skill_mentions=skill_mentions,
        command_prefix=command_prefix,
        urls=urls,
        file_paths=file_paths,
        mentioned_entities=mentioned_entities,
        has_question=has_q,
        imperative_verbs=imperative_verbs,
        char_length=len(raw),
        word_count=word_count,
        script_families=script_families,
        truncated_input=truncated,
    )
