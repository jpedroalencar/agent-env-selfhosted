# Final Repository Organization Review

**Status:** Pre-implementation review
**Date:** 2026-06-27
**Frozen principles:** Platform owns intelligence. Hermes Runtime owns execution. Hermes Runtime is external. Platform is canonical. Adapters isolate.

---

## 1. Directory Review

| Directory | Recommendation | Justification |
|-----------|---------------|---------------|
| `platform/` | **Remain unchanged** | Core Platform layer. Contains frozen contracts (`contracts/`) and placeholder directories for all 8 declared subsystems. Every subdirectory maps to a responsibility in the frozen architecture. |
| `adapters/` | **Remain unchanged** | Single integration point between Platform and Hermes Runtime. Three modules, three responsibilities. Clean boundary. |
| `agent/` | **Remain unchanged** | Persona identity definitions (`personas/`), memory schemas (`memory/`), and future home for migrated domain skills (`skills/`). Note: persona files are currently duplicated in `~/.hermes/skills/personas/`. During implementation, in-repo becomes canonical. |
| `artifacts/` | **Remain unchanged** | Knowledge Vault. Working subsystem with registry, 10 artifacts, automated scripts. Core Platform intelligence. |
| `apps/` | **Remain unchanged** | Application registry. Empty but has a declared purpose documented in its README. Intentionally retained for future application definitions built on the Platform. |
| `config/` | **Remain unchanged** | Platform configuration. Currently `routing.yaml`. Will grow with `memory-policies.yaml`, `knowledge-providers.yaml` in later phases. |
| `docs/` | **Remain unchanged** | Platform documentation. Well-organized: `specifications/`, `workflows/`, `reviews/`. `docs/build-log.md` is a deliberate redirect to `log/build-log.md` — no duplication. |
| `diagrams/` | **Remain unchanged** | Architecture diagrams. Three files, focused, valuable. |
| `infra/` | **Remain unchanged** | Empty. Intentionally retained for future infrastructure configuration (Caddy, deployment configs — Phase 8). |
| `log/` | **Remain unchanged** | Canonical engineering journal (`build-log.md`). Single file, append-only. |
| `logs/` | **Remove** | Empty directory with only `.gitkeep`. Gitignored by `.gitignore` line 75. Created at repo init but superseded by `log/` (singular). Serves no purpose — operational logs belong outside the repository. |
| `scripts/` | **Remain unchanged** | Automation scripts for backup, vault management, artifact lifecycle. May eventually be partially migrated to `platform/` Python modules, but that is implementation, not organization. |
| `screenshots/` | **Remove** | Empty since repo init (June 23). Never used. Referenced in 4 docs only as a line item in directory tree listings. No future architectural purpose — diagrams live in `diagrams/`. |
| `workspaces/` | **Remain unchanged** | Temporary agent workspaces. Intended to be gitignored. Minor issue: `.gitignore` has no `workspaces/` exclusion rule. Fix `.gitignore`, not the directory. |
| `.hermes/` | **Remain unchanged** | Already gitignored (`.gitignore` line 136). Contains `vault-logs/` — operational log output from vault scripts. Correctly excluded from version control. |

---

## 2. Directories Recommended for Cleanup

| Directory | Action | Reason |
|-----------|--------|--------|
| `logs/` | Delete directory and `.gitkeep` | Empty since creation. Gitignored. Superseded by `log/`. No purpose. |
| `screenshots/` | Delete directory and `.gitkeep` | Empty since creation. Never used. No future purpose. |

**Impact:** Zero. Neither directory contains any content. Their `.gitkeep` files are the only tracked objects. Removing them reduces the directory count from 17 to 15 without losing anything.

---

## 3. Directories Intentionally Retained (Empty, Future Purpose)

| Directory | Future Responsibility | Phase |
|-----------|----------------------|-------|
| `infra/` | Caddy configuration, deployment configs, Docker/compose files | 8 |
| `apps/` | Application definitions built on the Platform | Ongoing |
| `agent/skills/` | Migrated domain skills from `~/.hermes/skills/` | 2+ |
| `platform/dispatch/` | Intent classification, routing, ExecutionPlan production | 2 |
| `platform/context/` | Context strategy, vault provider | 3 |
| `platform/memory/` | Memory orchestration, tier policies | 4 |
| `platform/knowledge/` | Knowledge provider framework, vault and web providers | 5 |
| `platform/telemetry/` | Event collection, storage, reporting | 6 |
| `platform/benchmarks/` | Benchmark runner, suites, scoring | 7 |
| `platform/gateway/` | API gateway, OAuth integration | 8 |

Every empty directory maps to a declared subsystem in the frozen architecture. None are speculative.

---

## 4. Data Ownership

### 4.1 Platform-Owned Data

| Data Category | Current Location | Owner | Notes |
|---------------|-----------------|-------|-------|
| User memory (agent notes) | `~/.hermes/memories/MEMORY.md` | **Platform** | Content is intelligence. Hermes persists mechanically via `memory_manager.py`. |
| User profile | `~/.hermes/memories/USER.md` | **Platform** | User preferences and identity. Platform intelligence. |
| Persona memory | `~/.hermes/personas/*/memory.md` | **Platform** | Per-persona domain knowledge. Content owned by Platform. |
| Persona identity | `agent/personas/*.md` (repo) + `~/.hermes/skills/personas/` | **Platform** | In-repo becomes canonical during migration. |
| Knowledge Vault index | `artifacts/index.md` | **Platform** | Artifact registry with metadata. |
| Knowledge Vault artifacts | `artifacts/<persona>/` | **Platform** | Generated research, analysis, reports. |
| Routing rules | `config/routing.yaml` | **Platform** | Intent-to-profile mappings. |
| Memory tier policies | `config/memory-policies.yaml` (future) | **Platform** | Per-intent memory strategy. |
| Knowledge provider config | `config/knowledge-providers.yaml` (future) | **Platform** | Provider registration and priority. |
| Telemetry events | `platform/telemetry/store.py` (future) | **Platform** | Execution events, latency, token usage, errors. |
| Telemetry reports | `platform/telemetry/reports.py` (future) | **Platform** | Aggregations, trends, dashboards. |
| Benchmark results | `platform/benchmarks/` (future) | **Platform** | Test scores, regression data, historical trends. |
| Benchmark suites | `platform/benchmarks/suites/` (future) | **Platform** | Prompt sets, expected behaviors, scoring rubrics. |
| Domain skills | `agent/skills/` (future) | **Platform** | Reusable procedures for financial analysis, research, dev, ops. |
| ExecutionPlans | In-memory (future: telemetry store) | **Platform** | Plans produced by dispatch. May be logged for telemetry. |

### 4.2 Hermes Runtime-Owned Data

| Data Category | Current Location | Owner | Notes |
|---------------|-----------------|-------|-------|
| Conversation transcripts | `~/.hermes/state.db` | **Hermes Runtime** | Full message history. Session persistence. |
| Session state | `~/.hermes/state.db` | **Hermes Runtime** | Active session tracking, metadata. |
| Tool execution records | `~/.hermes/state.db` | **Hermes Runtime** | Tool call history within sessions. |
| System prompt cache | In-memory (agent loop) | **Hermes Runtime** | Cached across turns for prefix caching. |
| Context compression state | In-memory (`context_compressor`) | **Hermes Runtime** | Token thresholds, compression history. |
| Credential state | `~/.hermes/auth.json` | **Hermes Runtime** | OAuth tokens, credential pools. |
| Provider model cache | `~/.hermes/models_dev_cache.json` | **Hermes Runtime** | Available models per provider. |
| Context length cache | `~/.hermes/context_length_cache.yaml` | **Hermes Runtime** | Per-model context window sizes. |
| Rate limit state | In-memory (`rate_limit_tracker`) | **Hermes Runtime** | Per-provider rate limit counters. |
| Gateway platform state | `~/.hermes/gateway_state.json` | **Hermes Runtime** | Chat platform connection status. |
| Gateway channel directory | `~/.hermes/channel_directory.json` | **Hermes Runtime** | Known chat channels and threads. |
| Cron job definitions | `~/.hermes/cron/` | **Hermes Runtime** | Schedule definitions. Job content may be Platform. |
| Cron job output | `~/.hermes/cron/output/` | **Shared** | Execution owns scheduling and delivery. Platform owns the content of what was produced. |

### 4.3 Adapter-Owned Data

| Data Category | Current Location | Owner | Notes |
|---------------|-----------------|-------|-------|
| Hermes capability view | In-memory (`adapters/hermes/config.py`) | **Adapter** | Read-only snapshot of available providers, models, toolsets. |
| Plan translation mapping | In-memory (`adapters/hermes/executor.py`) | **Adapter** | Mechanical field mapping. No persistent state. |

### 4.4 Shared Data (Unavoidable)

| Data Category | Current Location | Shared By | Why Shared |
|---------------|-----------------|-----------|------------|
| Hermes operational config | `~/.hermes/config.yaml` | Platform (reads) + Hermes (owns) | Platform reads provider/model availability to validate plans. Hermes owns the config file. |
| API secrets | `~/.hermes/.env` | Hermes (owns) | Platform never reads secrets directly. Hermes manages credentials. |
| Cron job content | `~/.hermes/cron/` | Platform (defines) + Hermes (executes) | Platform defines what jobs do. Hermes executes them on schedule. |

---

## 5. Future SQLite Ownership

When the Platform introduces its own SQLite database (distinct from Hermes' `state.db`):

### Platform SQLite Owns

| Data | Justification |
|------|--------------|
| Telemetry events | Raw execution events — Platform intelligence about runtime behavior. |
| Telemetry aggregations | Pre-computed reports (latency p50/p95, error rates, token costs per task). |
| Benchmark results | Historical scores, regression data, per-suite trends. Platform evaluates quality. |
| Knowledge Vault metadata | Artifact index entries, freshness timestamps, usage statistics, reuse decisions. Augments `artifacts/index.md` without replacing it. |
| Routing effectiveness | Classification accuracy per intent, misrouting events, fallback-to-orchestrator rate. |
| Memory orchestration log | Which tier was activated per task, persistence decisions, wipe events. |
| ExecutionPlan history | Plans produced by dispatch — for debugging classification and routing. |

### Hermes state.db Continues to Own

| Data | Justification |
|------|--------------|
| Conversation transcripts | Hermes Runtime owns execution records. |
| Session state | Runtime lifecycle management. |
| Tool execution records | What tools ran, with what results, in what order. |
| Gateway channel state | Chat platform connection metadata. |

### Boundary

> Platform SQLite owns intelligence ABOUT execution. Hermes state.db owns the execution records themselves. Platform queries Hermes state.db only through the Adapter's read-only config view — never directly.

---

## 6. Remaining Repository Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Persona files duplicated between `agent/personas/` and `~/.hermes/skills/personas/` | Low | Implementation Phase 2 declares in-repo canonical. Hermes skill versions become symlinks or are removed. |
| `workspaces/` not gitignored despite README claiming it is | Low | Add `workspaces/*` to `.gitignore`. Keep `.gitkeep` for directory structure. |
| Vault scripts write logs to `.hermes/vault-logs/` inside repo | Low | Already gitignored. Consider relocating to `~/.hermes/vault-logs/` or `artifacts/.vault-logs/` for clarity. |
| `docs/build-log.md` redirect could be missed by tools that don't follow markdown links | Low | Acceptable. The redirect is human-readable. |
| `.gitignore` has `logs/` (line 75) but `log/` (singular, not gitignored) is the canonical journal | Low | Removing `logs/` directory resolves the ambiguity. |

---

## 7. Repository Freeze Recommendation

**The repository organization is ready to be frozen.**

All 15 remaining directories have a clear architectural purpose:

- 11 Platform directories (intelligence, configuration, documentation)
- 1 Adapter directory (integration boundary)
- 3 Temporary/operational directories (workspaces, .hermes, .git — all correctly gitignored or version-control internals)

The two directories recommended for removal (`logs/`, `screenshots/`) are empty and serve no purpose. Their removal is cleanup, not architectural change.

No directory is ambiguous. No directory has an unclear owner. No directory is speculative — every empty directory maps to a declared subsystem in the frozen architecture.

**Implementation can proceed.**
