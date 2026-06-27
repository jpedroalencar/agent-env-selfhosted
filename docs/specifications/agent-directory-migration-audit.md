# Migration Audit — agent/ Directory

**Architecture v3.0 (frozen). Evaluation only.**

---

## 1. Inventory

```
agent/
├── memory/
│   ├── decision-log-template.md     # ADR template
│   ├── memory-schema.md             # 5-category schema definition
│   ├── persona-memory-template.md   # Per-persona memory template
│   └── project-memory-template.md   # Project state template
├── personas/
│   ├── dev.md                       # Dev persona definition
│   ├── financial-analyst.md         # FA persona definition
│   ├── operations-manager.md        # OM persona definition
│   └── research-analyst.md          # RA persona definition
└── skills/
    └── .gitkeep                     # Empty placeholder
```

---

## 2. Classification

| Subdirectory | Owner | Type | Depends On | Depended On By |
|-------------|-------|------|------------|----------------|
| `agent/memory/` | **Platform** | Documentation | Nothing | Nothing (zero code references) |
| `agent/personas/` | **Platform** | Reference definition | Nothing | Hermes Runtime (operationally, via duplicates at `~/.hermes/skills/personas/`) |
| `agent/skills/` | **Platform** | Placeholder | Nothing | Nothing (empty) |

---

## 3. Analysis

### 3.1 agent/memory/ — Misclassified

The four files in `agent/memory/` are **documentation**, not code. They describe the Platform's five-category memory architecture (long-term, project, decision, operational, research). They contain no implementation, no runtime data, no code dependencies.

**Architectural conformance:** These belong under `docs/`, not `agent/`. The Platform architecture places all implementation in `pilot/` and all documentation in `docs/`. The `agent/` directory should hold agent configuration assets (personas, skills), not design documentation.

**Recommendation:** Move to `docs/memory-schemas/`. Update any internal cross-references. Eight characters added to file paths; zero code impact.

### 3.2 agent/personas/ — Correct Location, Stale Content

The four persona files define what each persona knows, owns, and refuses to own. This is Platform intelligence — the Platform decides which persona handles which intent.

**The duplication problem:** The in-repo files differ from the operational Hermes versions at `~/.hermes/skills/personas/*/SKILL.md`. The Hermes versions use SKILL.md format with YAML frontmatter (`name`, `version`, `workspace`). The in-repo versions are detailed reference documents with sections on responsibilities, authority boundaries, inputs/outputs, memory scope, routing rules, escalation rules, collaboration rules, and artifact generation procedures.

These are NOT duplicates — they serve different purposes:
- **In-repo** (`agent/personas/dev.md`): Canonical reference. Describes what the persona IS.
- **Hermes** (`~/.hermes/skills/personas/dev/SKILL.md`): Operational skill. Describes how Hermes loads and executes the persona.

Both are Platform-owned. The in-repo version should be the source of truth; the Hermes version should be derived from it.

**Recommendation:**
1. Keep `agent/personas/` where it is. It is correctly placed.
2. Add an `agent/README.md` declaring this directory as the canonical source for persona definitions.
3. During Phase 2, reconcile the in-repo definitions with the Hermes operational versions. The in-repo versions become authoritative.

### 3.3 agent/skills/ — Correct Placeholder

Empty with `.gitkeep`. The migration spec (Phase 2) plans to migrate domain skills from `~/.hermes/skills/` into this directory. Correctly positioned — Platform-owned skill definitions that Hermes Runtime loads.

**Recommendation:** Keep as-is. Populate during Phase 2.

---

## 4. Architectural Conformance

| Check | Status |
|-------|--------|
| Content is Platform-owned (intelligence, not execution) | ✅ All content is Platform intelligence |
| Content is in the correct repository (agent-env-selfhosted) | ✅ Platform repo |
| Directory name conforms to Architecture v3.0 | ⚠️ `agent/` is ambiguous — could imply Runtime. But content is clearly Platform. |
| No Runtime dependencies | ✅ Zero code references from `pilot/`, `adapters/`, or Hermes |
| No circular dependencies | ✅ Clean |

**Verdict:** The directory is architecturally correct. `agent/memory/` is the only subdirectory misplaced — it's documentation that belongs in `docs/`.

---

## 5. Migration Plan

| Step | Action | Files Affected | Disruption |
|------|--------|---------------|------------|
| 1 | Create `docs/memory-schemas/` | 1 new directory | None |
| 2 | Move 4 files: `agent/memory/*.md` → `docs/memory-schemas/` | 4 moved | None |
| 3 | Remove `agent/memory/` (now empty) | 1 directory removed | None |
| 4 | Create `agent/README.md` declaring canonical source status | 1 new file | None |
| 5 | Update any doc references to `agent/memory/` paths | ~2 references | None |

**Total:** 5 operations, zero code changes, zero test impact, zero runtime impact.

### Files to move

```
agent/memory/decision-log-template.md     → docs/memory-schemas/decision-log-template.md
agent/memory/memory-schema.md             → docs/memory-schemas/memory-schema.md
agent/memory/persona-memory-template.md   → docs/memory-schemas/persona-memory-template.md
agent/memory/project-memory-template.md   → docs/memory-schemas/project-memory-template.md
```

### agent/README.md (proposed content)

```markdown
# Agent Configuration

Platform-owned agent assets. These files define what personas know,
how memory is structured, and which skills are available. They are
the canonical source; Hermes Runtime loads operational versions
derived from these definitions.

- `personas/` — Persona identity definitions (responsibilities, boundaries, routing)
- `skills/` — Domain skill definitions (future: migrated from ~/.hermes/skills/)
```

---

## 6. Recommendation

**Proceed with migration.** The `agent/` directory is architecturally correct. Only `agent/memory/` needs to move — from `agent/` (which should hold configuration assets, not documentation) to `docs/` (which is the canonical documentation location).

The directory name `agent/` should remain. It correctly describes "agent configuration assets" and has no connotation of Runtime ownership. Renaming would break git history and documentation references with no architectural benefit.
