# Memory Schema

Defines the five memory categories used by the self-hosted AI agent platform. This schema is implementation-agnostic — it describes what information is stored and how it is organized, without prescribing file, database, or vector-based storage.

**Domain:** Agent Platform (`agent-env-selfhosted`)
**Scope:** Definition only. This file contains no runtime data, no conversation history, and no generated memory artifacts.

---

## 1. Long-Term Memory

### Purpose
Persistent knowledge that survives session resets and container rebuilds. Stores the agent's identity, configured behavior, domain expertise, and accumulated operational wisdom.

### Contents

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `agent_identity` | text | Fixed identity text used across all sessions | "You run on Hermes Agent..." |
| `configured_personas` | list | Active persona definitions with routing rules | FA, RA, Dev, OM |
| `domain_rules` | list | Cross-domain operational constraints | Git safety rules, approval preferences |
| `accumulated_knowledge` | list | Verified facts learned across sessions | Tool quirks, preferred workflows |
| `last_updated` | timestamp | When this record was last modified | 2026-06-23T14:00:00Z |

### Update Rules
- **Append-only for accumulated knowledge.** Do not overwrite verified facts.
- **Correction over removal.** If a fact is wrong, add a correction entry with the date. Do not delete the original.
- **On container rebuild:** Loaded from repository definitions (`agent/` directory) and repopulated from the last backup of runtime memory.

---

## 2. Project Memory

### Purpose
Tracks the state of active platform projects: what's being worked on, what decisions have been made, what's blocked, and what's next.

### Contents

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `project_name` | text | Short identifier | "agent-env-selfhosted" |
| `current_phase` | text | Active phase from roadmap | "Phase 1 — Foundation" |
| `goals` | list | Current sprint or phase objectives | ["Establish repo structure", "Create docs"] |
| `constraints` | list | Active constraints affecting work | ["No CI/CD until Phase 3", "ARM-only deployment"] |
| `architecture_decisions` | list | ADRs with date, decision, reasoning | See decision-log-template.md |
| `known_issues` | list | Open bugs or blockers | ["hermes update shows 79 commits behind"] |
| `next_actions` | list | Prioritized task queue | ["Review Hermes update", "Add docs/security.md"] |
| `dependencies` | list | External dependencies with status | [{"name": "DeepSeek API", "status": "operational"}] |
| `last_updated` | timestamp | Last modification time | 2026-06-23T14:00:00Z |

### Update Rules
- **Operations Manager owns** project memory structure and accuracy.
- **All personas contribute** by reporting completion status and decisions.
- **Prune completed items** to the archive section. Keep the active section focused.

---

## 3. Decision Memory

### Purpose
Records engineering and operational decisions with context, rationale, and consequences. Serves as the persistent equivalent of the build log.

### Contents

| Field | Type | Description |
|-------|------|-------------|
| `decision_id` | text | Unique identifier (e.g., `DEC-20260623-001`) |
| `date` | date | When the decision was made |
| `author` | text | Persona or human who made the decision |
| `decision` | text | One-line summary of what was decided |
| `context` | text | Background and problem statement |
| `alternatives` | list | Options considered with trade-offs |
| `reasoning` | text | Why this option was chosen |
| `impact` | text | Expected consequences (positive and negative) |
| `follow_up` | list | Actions required as a result |
| `status` | enum | `proposed`, `accepted`, `implemented`, `superseded` |

### Update Rules
- **Create on every significant decision.** If in doubt, record it. Small decisions compound.
- **Supersede, don't delete.** If a decision is reversed, create a new entry with `status: superseded` and reference the replacement.
- **Link related decisions.** Use `decision_id` references to build a decision graph.

---

## 4. Operational Memory

### Purpose
Day-to-day operational state: active procedures, scheduled tasks, infrastructure metrics, and health status.

### Contents

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `active_procedures` | list | Currently defined SOPs | ["Container backup", "Credential rotation"] |
| `scheduled_tasks` | list | Cron jobs and one-shot scheduled tasks | [{"schedule": "daily 9am", "task": "disk usage report"}] |
| `infrastructure_state` | dict | Current resource utilization | {"disk_used_gb": 7.2, "disk_total_gb": 40, "uptime_days": 14} |
| `service_health` | dict | Status of external dependencies | {"deepseek": "operational", "telegram": "operational"} |
| `maintenance_log` | list | Recent maintenance actions | [{"date": "2026-06-23", "action": "container snapshot"}] |
| `last_updated` | timestamp | Last modification time | 2026-06-23T14:00:00Z |

### Update Rules
- **Dev owns** infrastructure state and service health.
- **Operations Manager owns** procedures and scheduled tasks.
- **Auto-expire** health data older than 30 days unless archived.

---

## 5. Research Memory

### Purpose
Cumulative research knowledge: topics covered, sources evaluated, findings stored. Prevents redundant research and builds a referenceable knowledge base.

### Contents

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `research_id` | text | Unique identifier | `RES-20260623-001` |
| `topic` | text | Research topic or question | "LXD vs Docker for agent workloads" |
| `date` | date | When the research was conducted | 2026-06-23 |
| `author` | text | Persona who performed the research | RA |
| `key_findings` | list | Summary of conclusions | ["LXD provides better filesystem isolation"] |
| `sources` | list | Sources consulted with quality rating | [{"url": "...", "rating": "high"}] |
| `confidence` | enum | Certainty level | `high`, `medium`, `low` |
| `gaps` | list | Information not found or uncertain | ["No ARM-specific benchmarks found"] |
| `related_research` | list | References to other research IDs | ["RES-20260620-002"] |

### Update Rules
- **Research Analyst owns** research memory structure and entries.
- **All personas may query** research memory before starting new research.
- **Before starting new research**, check if the topic has been covered. If the existing research has low confidence or is stale (>90 days), re-run.

---

## Storage Notes

### Implementation-Agnostic Design
This schema defines **what** is stored, not **how** it is stored. Implementations may use:

- **Filesystem** — Markdown files with YAML frontmatter (current approach)
- **Database** — SQLite with typed columns
- **Vector Store** — Embeddings for semantic retrieval

All three approaches can store the same fields. The schema does not prescribe any particular backend.

### What Never Goes in Memory
Regardless of storage implementation, the following must never be written to any memory category:

- Credentials, API keys, tokens, or secrets
- Conversation history or session transcripts
- Runtime log contents (summaries and patterns are acceptable)
- Raw API responses or endpoint payloads
- Personal identifiable information (PII)
- Licensed or proprietary third-party content
