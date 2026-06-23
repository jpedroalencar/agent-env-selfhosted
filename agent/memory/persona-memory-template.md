# Persona Memory Template

Template for persona-specific memory files. Each persona maintains its own memory file scoped to its domain. This file is read on persona activation and appended on task completion.

**Location:** `~/.hermes/personas/<persona-name>/memory.md`

---

## Agent Identity

```yaml
name: <persona-name>
role: <one-line role description>
reports_to: Orchestrator
scope: <domain boundaries — one paragraph>
```

## Known Projects

<!-- List of projects this persona has worked on, with status. -->

| Project | Status | Last Active | Key Contributions |
|---------|--------|-------------|-------------------|
| | | | |

## Preferences

<!-- Persona-specific preferences that affect how work is performed. -->

- **Output format:** <e.g., "Always include a JSON summary", "Markdown with tables">
- **Depth preference:** <e.g., "Thorough with cited sources", "Concise executive summary">
- **Tooling preference:** <e.g., "Prefer Python over shell scripts">
- **Communication style:** <e.g., "Structured, bullet-driven", "Technical and precise">

## Open Tasks

<!-- Active tasks assigned to this persona. Updated by Operations Manager. -->

| Priority | Task | Assigned | Dependencies | Status |
|----------|------|----------|--------------|--------|
| | | | | |

## Active Context

<!-- Current working context — what was in progress, what was learned last session. -->

### Current Focus

<One-paragraph description of what this persona was working on last.>

### Recent Work Log

| Date | Task | Outcome | Notes |
|------|------|---------|-------|
| YYYY-MM-DD | | | |

### Key Decisions Made

| Date | Decision | Rationale |
|------|----------|-----------|
| YYYY-MM-DD | | |

## Archived Context

<!-- Completed tasks and superseded decisions. Moved here from Active Context when no longer relevant. Kept for reference. -->

### Completed Projects

| Project | Completed | Summary |
|---------|-----------|---------|
| | | |

### Superseded Decisions

| Date | Decision | Superseded By | Rationale |
|------|----------|---------------|-----------|
| | | | |

---

## Usage Rules

1. **Read on activation:** Load this file at the start of every persona session.
2. **Append on completion:** After each task, append new findings, decisions, and completed items. Do not overwrite historical entries.
3. **Scope strictly:** Only store information within the persona's defined domain. See individual persona definitions for scope boundaries.
4. **Never store:** Credentials, API keys, tokens, conversation transcripts, raw API responses, or personal information.
5. **Archive completed items:** Move completed tasks from "Open Tasks" to "Archived Context" periodically. Keep Active Context focused on current work.
