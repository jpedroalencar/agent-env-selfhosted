# Project Memory Template

Template for tracking active platform projects. Owned by the Operations Manager persona. Each active project gets one document following this structure.

**Location:** `~/.hermes/content/orchestrator/project-memory.md` or project-specific file under `agent/memory/`

---

## Project Overview

```yaml
project_name: <project-name>
current_phase: <phase from roadmap>
status: active | paused | completed | archived
started: YYYY-MM-DD
last_updated: YYYY-MM-DD
owner: <persona or human>
```

**Description:**

<One-paragraph description of the project scope and objectives.>

## Goals

<!-- Current phase or sprint goals. Ordered by priority. -->

- [ ] Goal 1: <description>
- [ ] Goal 2: <description>
- [ ] Goal 3: <description>

## Constraints

<!-- Known constraints that limit options or approaches. -->

| Constraint | Type | Source | Expires |
|------------|------|--------|---------|
| | technical / resource / policy | | YYYY-MM-DD or N/A |

## Architecture Decisions

<!-- Significant decisions made during this project. Link to decision-log for full records. -->

| ID | Date | Decision | Status | Link |
|----|------|----------|--------|------|
| DEC-YYYYMMDD-NNN | YYYY-MM-DD | | accepted / superseded | [Full record]() |

## Known Issues

<!-- Open bugs, blockers, and risks. -->

| ID | Description | Severity | Status | Owner |
|----|-------------|----------|--------|-------|
| | | critical / high / medium / low | open / in-progress / resolved | |

## Next Actions

<!-- Prioritized list of next steps. Updated after each completed action. -->

| Priority | Action | Owner | Dependencies | Notes |
|----------|--------|-------|--------------|-------|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |

---

## Progress Log

<!-- Chronological log of significant events, completions, and blockers. -->

| Date | Event | Detail |
|------|-------|--------|
| YYYY-MM-DD | | |

---

## Usage Rules

1. **Operations Manager owns** this file. Updates are made by OM after receiving completion reports from other personas.
2. **All personas contribute** by reporting completed work, decisions, and blockers to OM.
3. **Archive when complete.** When a phase or project is complete, move to the archives directory. Do not delete.
4. **Cross-reference decisions.** Link to decision-log entries for full context behind architecture decisions.
5. **Review at least weekly.** OM reviews project memory weekly to update status, reprioritize, and identify blockers.
