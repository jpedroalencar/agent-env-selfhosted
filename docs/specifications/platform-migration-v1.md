# Platform Migration Specification v1.0

**Status:** Draft
**Author:** Lead Systems Engineer
**Date:** 2026-06-27
**Depends on:** Architecture Decision — Platform owns intelligence, Hermes Runtime owns execution (frozen)

---

## 1. Architectural Boundary

```
┌─────────────────────────────────────────┐
│              PLATFORM                    │
│         (agent-env-selfhosted)           │
│                                         │
│  Owns: intelligence, strategy, content  │
│                                         │
│  • Gateway (ingress, auth, routing)     │
│  • Context Planner (what to load)       │
│  • Context System (how to assemble)     │
│  • Knowledge Providers (where from)     │
│  • Progressive Loading (what priority)  │
│  • Prompt Builder (semantic composition)│
│  • Telemetry (what to measure)          │
│  • Benchmarks (what to test)            │
│  • Memory Orchestration (strategy)      │
│                                         │
│              │                          │
│              │  ExecutionPlan            │
│              │  (single contract)        │
│              ▼                          │
│                                         │
│         HERMES ADAPTER                  │
│    (translates Plan → Runtime params)   │
│                                         │
│              │                          │
│              ▼                          │
│                                         │
│         HERMES RUNTIME                  │
│         (hermes-agent)                  │
│                                         │
│  Owns: execution, mechanics, transport  │
│                                         │
│  • Prompt execution (model calls)       │
│  • Tool execution (dispatch, guardrails)│
│  • Model communication (transports)     │
│  • Streaming (token delivery)           │
│  • Runtime lifecycle (init, loop)       │
│  • Chat platform adapters (Telegram)    │
│  • Skill execution engine               │
│  • Context compression (mechanical)     │
│  • Credential management                │
│  • Session persistence                  │
└─────────────────────────────────────────┘
```

The Platform is the canonical engineering project. Hermes Runtime is an implementation dependency. No Platform intelligence lives in Hermes. No Hermes execution mechanics live in the Platform. The Adapter is the single integration point between them.

---

## 2. Repository Structure

### 2.1 Current Structure

```
agent-env-selfhosted/
├── agent/                    # Persona definitions, memory schemas, skill templates
│   ├── memory/
│   │   ├── decision-log-template.md
│   │   ├── memory-schema.md
│   │   ├── persona-memory-template.md
│   │   └── project-memory-template.md
│   ├── personas/
│   │   ├── dev.md
│   │   ├── financial-analyst.md
│   │   ├── operations-manager.md
│   │   └── research-analyst.md
│   └── skills/
│       └── .gitkeep
├── apps/                     # Application definitions
│   └── README.md
├── artifacts/                # Knowledge Vault
│   ├── index.md              # Artifact registry
│   ├── dev/                  # (3 artifacts)
│   ├── financial-analyst/    # (1 artifact)
│   ├── operations-manager/   # (4 artifacts + host-validation/)
│   └── research-analyst/     # (2 artifacts)
├── diagrams/                 # Architecture diagrams
│   ├── current-architecture.drawio
│   ├── current-architecture.md
│   └── sequence-research.md
├── docs/                     # Platform documentation
│   ├── architecture.md
│   ├── backup-recovery.md
│   ├── configuration.md
│   ├── deployment.md
│   ├── diagram-notes.md
│   ├── operations.md
│   ├── security.md
│   ├── reviews/              # Phase completion reviews
│   └── workflows/            # Workflow definitions
│       ├── artifact-pipeline.md
│       ├── knowledge-vault.md
│       └── research-pipeline.md
├── infra/                    # Infrastructure config (empty)
├── log/                      # Engineering journal
│   └── build-log.md
├── scripts/                  # Automation scripts
│   ├── backup-container.sh
│   ├── freshness-check.sh
│   ├── generate-artifact.sh
│   ├── lookup-artifact.sh
│   ├── register-artifact.sh
│   ├── restore-container.sh
│   ├── reuse-artifact.sh
│   ├── stale-check-cron.sh
│   └── update-index-stats.sh
├── screenshots/              # (empty)
├── workspaces/               # (empty)
├── .gitignore
├── LICENSE
└── README.md
```

### 2.2 Target Structure

```
agent-env-selfhosted/                    # Canonical Platform repository
│
├── pilot/                                # Platform intelligence layer (NEW) — directs Hermes Runtime
│   ├── contracts/                       # Frozen architectural contracts
│   │   └── execution-plan-v1.md         # ExecutionPlan schema
│   ├── dispatch/                        # Intent → Profile → Plan
│   │   ├── classifier.py
│   │   ├── routing.py
│   │   └── plan.py
│   ├── context/                         # Context strategy
│   │   ├── strategy.py
│   │   └── providers/
│   │       └── vault.py
│   ├── memory/                          # Memory orchestration
│   │   ├── orchestrator.py
│   │   └── policies.py
│   ├── knowledge/                       # Knowledge provider framework
│   │   ├── provider.py
│   │   └── providers/
│   │       ├── vault.py
│   │       └── web.py
│   ├── telemetry/                       # Observability
│   │   ├── collector.py
│   │   ├── events.py
│   │   ├── store.py
│   │   └── reports.py
│   ├── benchmarks/                      # Performance evaluation
│   │   ├── runner.py
│   │   ├── scoring.py
│   │   └── suites/
│   └── gateway/                         # API gateway
│       ├── api.py
│       └── auth.py
│
├── adapters/                            # Hermes Adapter layer (NEW)
│   └── hermes/
│       ├── executor.py                  # Translates ExecutionPlan → run_conversation()
│       ├── callbacks.py                 # Telemetry hooks into Hermes callbacks
│       └── config.py                    # Hermes config bridge
│
├── agent/                               # Persona intelligence (EXISTING, expands)
│   ├── personas/                        # Persona identity definitions
│   │   ├── orchestrator.md              # UPDATED: consumes ExecutionPlan
│   │   ├── financial-analyst.md
│   │   ├── research-analyst.md
│   │   ├── dev.md
│   │   └── operations-manager.md
│   ├── memory/                          # Memory schemas
│   │   ├── memory-schema.md
│   │   ├── persona-memory-template.md
│   │   ├── project-memory-template.md
│   │   └── decision-log-template.md
│   └── skills/                          # Platform-owned skill definitions
│       └── (migrated from ~/.hermes/skills/ — domain skills only)
│
├── artifacts/                           # Knowledge Vault (EXISTING)
│   ├── index.md
│   ├── dev/
│   ├── financial-analyst/
│   ├── operations-manager/
│   └── research-analyst/
│
├── docs/                                # Platform documentation (EXISTING)
│   ├── architecture.md
│   ├── specifications/                  # NEW: formal specs
│   │   └── platform-migration-v1.md     # This document
│   ├── workflows/
│   └── reviews/
│
├── config/                              # Platform configuration (NEW)
│   ├── routing.yaml                     # Intent → Profile routing rules
│   ├── memory-policies.yaml             # Per-intent memory tier policies
│   └── knowledge-providers.yaml         # Provider registration and priority
│
├── log/                                 # Engineering journal (EXISTING)
├── diagrams/                            # Architecture diagrams (EXISTING)
├── scripts/                             # Automation (EXISTING, may shrink as Python replaces shell)
├── infra/                               # Infrastructure config
├── apps/                                # Application definitions
├── workspaces/                          # Temporary workspaces
├── .gitignore
├── LICENSE
└── README.md
```

### 2.3 What Moves

| Source | Destination | Reason |
|--------|-------------|--------|
| `~/.hermes/skills/personas/*/SKILL.md` | `agent/personas/*.md` | Persona identity is Platform intelligence. Already duplicated in-repo; in-repo becomes canonical. |
| `~/.hermes/skills/financial-analysis/`, `research/`, `github/`, `media/`, `productivity/`, `mlops/`, `data-science/`, `creative/`, `note-taking/`, `smart-home/`, `social-media/`, `email/` | `agent/skills/` | Domain skills are Platform content. |
| `~/.hermes/skills/software-development/hermes-*` | `agent/skills/` | Hermes configuration and authoring skills are Platform knowledge about the Runtime. |
| `~/.hermes/skills/software-development/plan`, `spike`, `systematic-debugging`, `test-driven-development`, `simplify-code`, `requesting-code-review`, `project-continuity`, `platform-documentation`, `artifact-generation` | `agent/skills/` | Software development methodology skills are Platform intelligence. |
| `~/.hermes/skills/devops/lxd-snapshots`, `gateway-restart`, `sidecar-services`, `kanban-*` | `agent/skills/` | Operational procedures are Platform intelligence. |
| `~/.hermes/skills/documentation/engineering-journal` | `agent/skills/` | Documentation workflow is Platform intelligence. |
| `~/.hermes/personas/*/memory.md` | `agent/personas/*/memory.md` (or stay in-place, loaded by Platform) | Persona memory content is Platform intelligence. |
| `~/.hermes/memories/MEMORY.md`, `USER.md` | Stay in-place. Platform Memory Orchestrator reads/writes them. | Content location doesn't change; control of what/when to read/write moves to Platform. |
| `~/.hermes/config.yaml` (routing, persona, skills config) | `config/routing.yaml`, `config/knowledge-providers.yaml` | Configuration that encodes strategy moves to Platform config. Provider/API config stays in Hermes. |
| `~/.hermes/content/` | Deprecated. All content lives in `artifacts/`. | Single source of truth for generated content. |

### 2.4 What Stays in Hermes Runtime

| Component | Location | Reason |
|-----------|----------|--------|
| Agent loop (`run_agent.py`, `conversation_loop.py`) | `hermes-agent/` | Core execution cycle. |
| Tool executor (`tool_executor.py`, `tool_dispatch_helpers.py`) | `hermes-agent/agent/` | Tool dispatch and guardrails. |
| Model transports (`transports/`) | `hermes-agent/agent/transports/` | Wire-level model communication. |
| Gateway chat adapters (`gateway/platforms/`) | `hermes-agent/gateway/platforms/` | Chat platform transport (Telegram, Discord, etc.). |
| Stream dispatch (`stream_consumer.py`, `stream_dispatch.py`) | `hermes-agent/gateway/` | Token streaming delivery. |
| Skill execution engine (`skill_utils.py`, `skill_preprocessing.py`, `skill_commands.py`) | `hermes-agent/agent/` | Skill loading, parsing, injection into system prompt. |
| Context compression (`context_compressor.py`, `context_engine.py`) | `hermes-agent/agent/` | Mechanical compaction at token thresholds. |
| @references expansion (`context_references.py`) | `hermes-agent/agent/` | Mechanical expansion of @file, @url, @diff. |
| System prompt assembly — mechanical (`system_prompt.py`, `prompt_builder.py`) | `hermes-agent/agent/` | Assembly of environment hints, tool guidance, skills index. |
| Memory manager — mechanical (`memory_manager.py`, `memory_provider.py`) | `hermes-agent/agent/` | Prefetch, sync, provider enforcement. |
| Credential management (`credential_pool.py`, `credential_sources.py`) | `hermes-agent/agent/` | API key lifecycle. |
| Rate limiting, retry, error classification | `hermes-agent/agent/` | API call mechanics. |
| Session database (`state.db`, session management) | `hermes-agent/`, `~/.hermes/sessions/` | Conversation persistence. |
| Cron scheduler (`cron/`) | `hermes-agent/cron/` | Schedule execution. |
| Kanban dispatcher | `hermes-agent/gateway/` | Multi-agent work queue mechanics. |
| `~/.hermes/skills/` — execution skills NOT owned by Platform | `~/.hermes/skills/` | Skills installed by Hermes hub that aren't Platform domain knowledge (e.g., `touchdesigner-mcp`, `comfyui` — user-installed tools). |
| `~/.hermes/config.yaml` — provider/API/operational config | `~/.hermes/config.yaml` | Provider endpoints, API keys, timeouts, compression thresholds. Operational, not strategic. |

---

## 3. Ownership Table

### 3.1 Platform Components (agent-env-selfhosted)

| # | Component | Current Location | Type |
|---|-----------|-----------------|------|
| P1 | Persona identity definitions | `agent/personas/*.md` + `~/.hermes/skills/personas/` | Content |
| P2 | Memory schemas (core/working/persistent) | `agent/memory/memory-schema.md` | Intelligence |
| P3 | Memory tier policies | `config/memory-policies.yaml` (NEW) | Intelligence |
| P4 | Knowledge Vault (artifacts, index, scripts) | `artifacts/` + `scripts/` | Intelligence |
| P5 | Knowledge Provider framework | `pilot/knowledge/` (NEW) | Intelligence |
| P6 | Context strategy | `pilot/context/` (NEW) | Intelligence |
| P7 | Intent classification | `pilot/dispatch/classifier.py` (NEW) | Intelligence |
| P8 | Routing rules | `config/routing.yaml` (NEW) | Intelligence |
| P9 | ExecutionPlan contract | `pilot/contracts/execution-plan-v1.md` (NEW) | Contract |
| P10 | Platform Dispatch | `pilot/dispatch/` (NEW) | Intelligence |
| P11 | Memory Orchestrator | `pilot/memory/orchestrator.py` (NEW) | Intelligence |
| P12 | Telemetry collector and reports | `pilot/telemetry/` (NEW) | Intelligence |
| P13 | Benchmark suites and scoring | `pilot/benchmarks/` (NEW) | Intelligence |
| P14 | API Gateway | `pilot/gateway/api.py` (NEW) | Intelligence |
| P15 | OAuth authentication | `pilot/gateway/auth.py` (NEW) | Intelligence |
| P16 | Caddy configuration | `infra/` (NEW) | Infrastructure |
| P17 | Architecture documentation | `docs/architecture.md` | Intelligence |
| P18 | Engineering journal | `log/build-log.md` | Intelligence |
| P19 | Workflow definitions | `docs/workflows/` | Intelligence |
| P20 | Diagrams | `diagrams/` | Intelligence |
| P21 | Domain skills (financial, research, github, etc.) | `agent/skills/` (migrated) | Content |
| P22 | Hermes-authoring skills | `agent/skills/` (migrated) | Content |
| P23 | Software development methodology skills | `agent/skills/` (migrated) | Content |
| P24 | Operational procedure skills | `agent/skills/` (migrated) | Content |
| P25 | Persona memory content | `agent/personas/*/memory.md` | Content |
| P26 | Agent memory content (MEMORY.md, USER.md) | `~/.hermes/memories/` — Platform-owned, Hermes-persisted | Content |
| P27 | Platform configuration | `config/` (NEW) | Configuration |
| P28 | LXD backup infrastructure | `scripts/backup-container.sh`, `scripts/restore-container.sh` | Infrastructure |
| P29 | Infrastructure scripts | `scripts/` | Infrastructure |

### 3.2 Hermes Runtime Components (hermes-agent)

| # | Component | Current Location | Type |
|---|-----------|-----------------|------|
| H1 | Agent initialization | `run_agent.py::AIAgent.__init__` | Execution |
| H2 | Conversation loop | `agent/conversation_loop.py::run_conversation` | Execution |
| H3 | Per-turn context setup | `agent/turn_context.py::build_turn_context` | Execution |
| H4 | Tool executor | `agent/tool_executor.py` | Execution |
| H5 | Tool dispatch | `agent/tool_dispatch_helpers.py` | Execution |
| H6 | Tool guardrails | `agent/tool_guardrails.py` | Execution |
| H7 | Model transports (Anthropic, Bedrock, Chat Completions, Codex) | `agent/transports/` | Execution |
| H8 | Streaming | `gateway/stream_consumer.py`, `gateway/stream_dispatch.py` | Execution |
| H9 | Gateway chat adapters (Telegram, Discord, Slack, etc.) | `gateway/platforms/` | Execution |
| H10 | Gateway session management | `gateway/session.py`, `gateway/run.py` | Execution |
| H11 | Skill execution engine | `agent/skill_utils.py`, `agent/skill_preprocessing.py`, `agent/skill_commands.py` | Execution |
| H12 | Skill hub integration | `agent/skill_bundles.py` | Execution |
| H13 | System prompt assembly (mechanical) | `agent/system_prompt.py`, `agent/prompt_builder.py` | Execution |
| H14 | @references expansion | `agent/context_references.py` | Execution |
| H15 | Context compression | `agent/context_compressor.py`, `agent/context_engine.py` | Execution |
| H16 | Memory manager (mechanical) | `agent/memory_manager.py`, `agent/memory_provider.py` | Execution |
| H17 | Credential management | `agent/credential_pool.py`, `agent/credential_sources.py` | Execution |
| H18 | Rate limiting | `agent/rate_limit_tracker.py`, `agent/nous_rate_guard.py` | Execution |
| H19 | Retry logic | `agent/retry_utils.py` | Execution |
| H20 | Error classification | `agent/error_classifier.py` | Execution |
| H21 | Session persistence | `hermes_state.py`, `~/.hermes/state.db` | Execution |
| H22 | Cron scheduler | `cron/scheduler.py`, `cron/jobs.py` | Execution |
| H23 | Provider configuration | `~/.hermes/config.yaml` (provider section) | Configuration |
| H24 | `.env` secrets | `~/.hermes/.env` | Configuration |
| H25 | Agent identity (SOUL.md) | `~/.hermes/SOUL.md` | Content (loaded by Hermes, owned by Platform) |

### 3.3 Hermes Adapter Components (agent-env-selfhosted/adapters/hermes/)

| # | Component | Responsibility |
|---|-----------|---------------|
| A1 | `executor.py` | Translates ExecutionPlan into `AIAgent` constructor parameters + `run_conversation()` arguments |
| A2 | `callbacks.py` | Registers Platform telemetry hooks into Hermes callbacks (`step_callback`, `tool_complete_callback`, etc.) |
| A3 | `config.py` | Reads Hermes `config.yaml` and `.env` to populate Platform knowledge about available providers, models, toolsets |

---

## 4. Adapter Responsibilities

The Hermes Adapter is the **single integration point** between Platform intelligence and Hermes execution. It has exactly three responsibilities:

### 4.1 Plan Translation

**Input:** `ExecutionPlan` (Platform)
**Output:** `HermesExecutionParams` (what Hermes needs)

```
ExecutionPlan                    HermesExecutionParams
─────────────                    ─────────────────────
profile              ──────►     profile parameter
skills               ──────►     skills parameter
system_message_override ───►     system_message parameter
preloaded_context    ──────►     user_message prefix
max_iterations       ──────►     max_iterations parameter
timeout_seconds      ──────►     timeout parameter
model_override       ──────►     model parameter
```

The adapter does NOT interpret the plan. It mechanically maps fields. If the plan is invalid (missing required fields), the adapter rejects it before Hermes is invoked.

### 4.2 Telemetry Bridging

Hermes emits execution events via callbacks. The adapter:

1. Registers Platform telemetry hooks during `AIAgent` construction
2. Translates raw Hermes callback data into Platform `TelemetryEvent` schemas
3. Forwards events to `pilot/telemetry/collector.py`

The adapter does NOT store, analyze, or interpret events. It only bridges.

### 4.3 Configuration Reading

The Platform needs to know what Hermes can do (available models, providers, toolsets) to produce valid ExecutionPlans. The adapter:

1. Reads `~/.hermes/config.yaml` and `~/.hermes/.env`
2. Exposes a read-only view of available providers, models, and enabled toolsets
3. Does NOT write to Hermes configuration

### 4.4 What the Adapter Does NOT Do

- Does not classify intent
- Does not plan context
- Does not orchestrate memory
- Does not validate execution results (validation is Platform responsibility, post-execution)
- Does not modify Hermes source code
- Does not intercept or modify the Hermes agent loop

---

## 5. ExecutionPlan Flow

### 5.1 Complete Flow

```
User Message
    │
    ▼
┌──────────────────────────────────────────────────────────┐
│  PLATFORM                                                │
│                                                          │
│  1. Platform Dispatch receives message + session context │
│     │                                                    │
│     ├── classify(message) → Intent                       │
│     │     (rule-based: research | financial | code |     │
│     │      ops | casual | multi-step)                    │
│     │                                                    │
│     ├── route(intent) → profile                          │
│     │     (routing.yaml: intent → persona profile)       │
│     │                                                    │
│     ├── MemoryOrchestrator.strategy_for(intent)          │
│     │     → MemoryStrategy (tiers, wipe policy)          │
│     │                                                    │
│     ├── KnowledgeResolver.query(intent)                  │
│     │     → [KnowledgeResult] (vault, web, memory)       │
│     │                                                    │
│     └── ContextStrategy.assemble(intent, knowledge,      │
│            memory) → preloaded_context                   │
│                                                          │
│  2. ExecutionPlan assembled                              │
│     {                                                    │
│       profile, skills, memory_tier,                      │
│       knowledge_providers, preloaded_context,            │
│       max_iterations, timeout_seconds,                   │
│       validation_criteria, expected_output_format        │
│     }                                                    │
│                                                          │
└──────────────────────┬───────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────┐
│  HERMES ADAPTER                                          │
│                                                          │
│  3. Plan → HermesExecutionParams                         │
│     executor.translate(plan) → params                    │
│                                                          │
│  4. Construct AIAgent(params)                            │
│     Register telemetry callbacks                         │
│                                                          │
└──────────────────────┬───────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────┐
│  HERMES RUNTIME                                          │
│                                                          │
│  5. run_conversation(user_message, system_message,       │
│        skills, max_iterations, callbacks)                │
│                                                          │
│     build_turn_context()                                 │
│       ├── system prompt (SOUL.md + skills + env hints)   │
│       ├── context compression (if needed)                │
│       ├── user message + preloaded_context               │
│       └── memory prefetch                                │
│                                                          │
│     Tool-calling loop                                    │
│       ├── LLM call                                       │
│       ├── tool dispatch (if tool_calls)                  │
│       └── repeat until text response                     │
│                                                          │
│  6. Return result                                        │
│     {                                                    │
│       response: str,                                     │
│       messages: [...],                                   │
│       usage: {tokens},                                   │
│       tool_calls: [...]                                  │
│     }                                                    │
│                                                          │
└──────────────────────┬───────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────┐
│  PLATFORM                                                │
│                                                          │
│  7. Validate result against validation_criteria          │
│     ├── format check (expected_output_format)            │
│     ├── citation check (must_cite_sources)               │
│     ├── data check (must_include_numeric_data)            │
│     └── code check (execution success)                   │
│                                                          │
│  8. MemoryOrchestrator.persist(strategy, result)         │
│     (if write_tier != None)                              │
│                                                          │
│  9. Deliver response to user                             │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### 5.2 ExecutionPlan Schema (Conceptual)

```
ExecutionPlan
├── profile: str                    # persona profile name
├── skills: [str]                   # skills to preload
├── memory_tier: enum               # persistent | working | none
├── knowledge_providers: [str]      # ordered: vault, web, session
├── preloaded_context: str          # assembled context string
├── system_message_override: str?   # rare: override persona identity
├── max_iterations: int             # tool-calling budget
├── timeout_seconds: int            # hard deadline
├── model_override: str?            # pin a model (rare)
├── validation_criteria: [str]      # post-execution checks
└── expected_output_format: str     # markdown_report | csv | code | free_text
```

### 5.3 What Happens When There Is No Plan

If the Platform cannot produce an ExecutionPlan (no classifier match, no routing rule):

1. Platform falls back to `profile = "orchestrator"` with empty context
2. The Orchestrator persona handles the request as it does today — via LLM-based routing
3. This is the **graceful degradation path**: the system always works, even when the Platform has no strategy

---

## 6. Migration Phases

### Phase 0: Foundation

**Goal:** Create the directory structure and contracts. No behavior change.

**Actions:**
1. Create `pilot/`, `adapters/`, `config/` directories
2. Create `docs/specifications/` directory, move this document there
3. Write `pilot/contracts/execution-plan-v1.md` — the formal contract
4. Create `adapters/hermes/` with stub modules (no implementation)
5. Create `config/routing.yaml` with current routing rules (extracted from Orchestrator persona)
6. Commit. Push.

**Deliverable:** Repository structure reflects the architecture. No code runs.

**Validation:** Directory structure matches this specification. Contract document follows architecture design skill template.

**Dependencies:** None.

---

### Phase 1: ExecutionPlan Contract

**Goal:** Define the ExecutionPlan as a frozen contract. Implement the data model.

**Actions:**
1. Implement `pilot/dispatch/plan.py` — ExecutionPlan dataclass
2. Implement `adapters/hermes/executor.py` — plan-to-params translation (mechanical mapping)
3. Write tests: valid plan → valid Hermes params; invalid plan → rejection
4. Freeze the contract once `adapters/hermes/executor.py` depends on it

**Deliverable:** ExecutionPlan exists as code. Adapter can translate it. No agent uses it yet.

**Validation:** Unit tests pass. Contract document is frozen.

**Dependencies:** Phase 0.

---

### Phase 2: Platform Dispatch

**Goal:** Platform actively classifies intent and routes to profiles.

**Actions:**
1. Implement `pilot/dispatch/classifier.py` — rule-based intent classification
2. Implement `pilot/dispatch/routing.py` — intent → profile lookup from `config/routing.yaml`
3. Implement `pilot/dispatch/__init__.py` — `dispatch(message, session) → ExecutionPlan`
4. Update Orchestrator persona to consume ExecutionPlan instead of doing free-form routing
5. Run existing delegation paths through the dispatcher (parallel to current flow, compare results)

**Deliverable:** Platform Dispatch produces ExecutionPlans. Orchestrator persona uses them.

**Validation:** Every existing delegation path (financial analysis, research, dev, ops, casual) produces a correct ExecutionPlan. No regression in persona behavior.

**Dependencies:** Phase 1.

---

### Phase 3: Context Strategy

**Goal:** Platform assembles context (vault + memory + skills) before Hermes execution.

**Actions:**
1. Implement `pilot/context/strategy.py` — ContextStrategy and ContextBlock
2. Implement `pilot/context/providers/vault.py` — Knowledge Vault as context provider
3. Integrate with Platform Dispatch: `preloaded_context` populated before plan is produced
4. Vault lookup becomes automatic — no persona needs to remember to grep artifacts/

**Deliverable:** Vault retrieval-before-research is automatic. Context blocks are assembled deterministically.

**Validation:** A research query hits the vault during context assembly. Stale artifacts are flagged. Fresh artifacts are injected. Personas never see the vault lookup — it's already done.

**Dependencies:** Phase 2.

---

### Phase 4: Memory Orchestration

**Goal:** Platform decides memory tier strategy. Hermes executes mechanically.

**Actions:**
1. Implement `pilot/memory/orchestrator.py` — MemoryOrchestrator
2. Implement `pilot/memory/policies.py` — per-intent tier policies
3. Create `config/memory-policies.yaml` — policy configuration
4. Integrate with Platform Dispatch: MemoryStrategy incorporated into ExecutionPlan
5. Implement pre-turn memory read (core + selected tier) injected into preloaded_context
6. Implement post-turn memory write (if write_tier != None)

**Deliverable:** Memory tier behavior is deterministic per intent. Working memory wiped between delegations. Persistent memory accumulated across sessions.

**Validation:** Financial analysis activates persistent memory. Casual chat uses working memory only. Core identity always loaded. Working memory empty after delegation completes.

**Dependencies:** Phase 3.

---

### Phase 5: Knowledge Provider Framework

**Goal:** Knowledge sources are pluggable. Vault is the first provider. Web search is the second.

**Actions:**
1. Implement `pilot/knowledge/provider.py` — KnowledgeProvider abstract class
2. Implement `pilot/knowledge/providers/vault.py` — wraps existing vault scripts
3. Implement `pilot/knowledge/providers/web.py` — controlled web search (Platform decides query)
4. Implement KnowledgeResolver — queries providers in priority order, deduplicates
5. Create `config/knowledge-providers.yaml` — provider registration
6. Integrate with Platform Dispatch: KnowledgeResolver results feed into ContextStrategy

**Deliverable:** Knowledge providers are registered and queried before every execution. Vault reuse is automatic. Web pre-search is controlled.

**Validation:** A new research query: vault checked first (no match), web searched second (controlled query), results injected into context. Persona never calls web_search for information the Platform already gathered.

**Dependencies:** Phase 3 (Context Strategy). Phase 4 recommended but not required.

---

### Phase 6: Telemetry

**Goal:** Platform collects structured execution data from Hermes callbacks.

**Actions:**
1. Implement `pilot/telemetry/events.py` — TurnStart, ToolCall, LLMCall, TurnEnd, Error schemas
2. Implement `pilot/telemetry/collector.py` — event ingestion
3. Implement `pilot/telemetry/store.py` — SQLite persistence
4. Implement `adapters/hermes/callbacks.py` — callback registration and event translation
5. Integrate with Adapter: register callbacks during AIAgent construction

**Deliverable:** Every execution produces structured telemetry events. Reports show latency, token usage, error rates, tool call frequency.

**Validation:** After 50 tasks, query telemetry store for: most-used persona, average latency, token cost per task, error rate.

**Dependencies:** Phase 1 (Adapter must exist). Can run parallel to Phases 3-5.

---

### Phase 7: Benchmarks

**Goal:** Platform evaluates system performance against defined test suites.

**Actions:**
1. Implement `pilot/benchmarks/runner.py` — sends prompts through Platform → Adapter → Hermes
2. Implement `pilot/benchmarks/scoring.py` — scoring framework
3. Implement `pilot/benchmarks/suites/routing.py` — routing accuracy
4. Implement `pilot/benchmarks/suites/retrieval.py` — vault reuse rate
5. Implement `pilot/benchmarks/suites/latency.py` — end-to-end timing

**Deliverable:** Benchmark runner exercises the full pipeline. Scores tracked over time.

**Validation:** Run routing benchmark: 20 prompts with known correct personas → accuracy ≥ 95%. Run retrieval benchmark: 10 prompts that should hit vault → reuse rate ≥ 30%.

**Dependencies:** Phase 2 (Platform Dispatch must work). Phase 6 (Telemetry) recommended.

---

### Phase 8: Gateway Architecture

**Goal:** Platform API Gateway handles programmatic access. Caddy handles TLS and routing. OAuth handles authentication. Hermes Gateway continues handling chat platforms.

**Actions:**
1. Implement `pilot/gateway/auth.py` — OAuth integration
2. Implement `pilot/gateway/api.py` — FastAPI server with `/api/chat`, `/api/telemetry`, `/api/benchmarks`
3. Configure Caddy: TLS termination, route `/telegram/webhook` → Hermes Gateway, route `/api/*` → Platform API, route `/dashboard` → static files
4. Deploy. Verify coexistence with Hermes Gateway.

**Deliverable:** External systems can call the Platform API. Users can authenticate via OAuth. Hermes Gateway unchanged.

**Validation:** `curl -X POST https://pilot/api/chat -H "Authorization: Bearer <token>" -d '{"message": "Analyze AAPL"}'` → structured response.

**Dependencies:** Phase 2 (Platform Dispatch). Phase 6 (Telemetry API endpoint).

---

## 7. Migration Dependency Graph

```
Phase 0: Foundation
    │
    ▼
Phase 1: ExecutionPlan Contract
    │
    ├──────────────────────────────┐
    ▼                              │
Phase 2: Platform Dispatch         │
    │                              │
    ├──────────┐                   │
    ▼          │                   │
Phase 3:      │                   │
Context       │                   │
Strategy      │                   │
    │         │                   │
    ▼         │                   │
Phase 4:      │                   │
Memory        │                   │
Orchestration │                   │
    │         │                   │
    ▼         │                   │
Phase 5:      │                   │
Knowledge     │                   │
Providers     │                   │
              │                   │
              ▼                   ▼
         Phase 6:            Phase 7:
         Telemetry           Benchmarks
              │                   │
              └────────┬──────────┘
                       ▼
                  Phase 8:
                  Gateway
                  Architecture
```

---

## 8. Risks

### R1: Hermes Upstream Changes

**Risk:** Hermes Agent is actively developed by Nous Research. Upstream changes to the agent loop, system prompt assembly, or tool dispatch could break the Adapter.

**Mitigation:**
- The Adapter depends on Hermes' public API surface (`AIAgent` constructor, `run_conversation()` parameters, callbacks). These are stable.
- The Adapter does not monkey-patch or subclass Hermes internals.
- Pin Hermes version. Test adapter against each Hermes upgrade before deploying.
- If a breaking change occurs, the Adapter is the only thing that needs updating. No Platform intelligence is affected.

**Severity:** Medium. Probability: Low (public API is stable).

### R2: Classification Errors

**Risk:** Rule-based intent classification produces wrong profiles. A financial query routed to Dev produces nonsense.

**Mitigation:**
- Classification is conservative: ambiguous intents fall back to the Orchestrator persona (current behavior).
- Classification rules are configurable in `config/routing.yaml` — can be tuned without code changes.
- Telemetry tracks classification accuracy (Phase 6). Benchmarks measure it (Phase 7).

**Severity:** Medium. Probability: Low (classification is rule-based, not ML; rules are tested).

### R3: Stale Knowledge Vault Injection

**Risk:** The vault injects stale artifacts as preloaded context, poisoning the model with outdated information.

**Mitigation:**
- Vault provider evaluates freshness before injection (Phase 3 uses Phase 2's freshness logic).
- Stale artifacts are flagged, not injected.
- The model can still call web_search for fresh information — the Platform preloads what it knows; Hermes fills gaps.

**Severity:** Low. Probability: Low (freshness check is deterministic).

### R4: Configuration Drift

**Risk:** Platform configuration (`config/`) and Hermes configuration (`~/.hermes/config.yaml`) diverge. The Platform thinks a provider is available that Hermes can't reach.

**Mitigation:**
- The Adapter's `config.py` reads Hermes configuration at startup and exposes current state.
- Platform Dispatch validates ExecutionPlans against available Hermes capabilities before execution.
- If a plan references an unavailable model or toolset, the Adapter rejects it with a diagnostic error.

**Severity:** Medium. Probability: Medium (two config sources).

### R5: Duplicate Skill Loading

**Risk:** Platform-owned skills (in `agent/skills/`) and Hermes-installed skills (in `~/.hermes/skills/`) have the same skill in both locations, causing double injection.

**Mitigation:**
- Migration Phase 2 removes moved skills from `~/.hermes/skills/`.
- The Adapter resolves skill paths: Platform skills take precedence; Hermes skills are fallback.
- Skill deduplication by name at load time.

**Severity:** Low. Probability: Low (controlled migration).

### R6: Increased Latency

**Risk:** Platform pre-processing (classification, vault lookup, memory read, knowledge provider queries) adds latency before Hermes even starts.

**Mitigation:**
- All pre-processing is deterministic and fast (no LLM calls in the Platform layer).
- Vault lookup is filesystem grep — milliseconds.
- Memory read is file read — milliseconds.
- Web pre-search is optional and cached.
- Parallelize independent operations (vault + memory reads can happen concurrently).

**Severity:** Low. Probability: Medium (adds latency, but sub-second for most paths).

---

## 9. Rollback Strategy

Every phase is additive. No phase modifies Hermes source code or removes existing behavior. Rollback is:

### Per-Phase Rollback

| Phase | Rollback Action |
|-------|----------------|
| 0 | Delete `pilot/`, `adapters/`, `config/` directories. Repository returns to current state. |
| 1 | Delete `pilot/dispatch/plan.py` and `adapters/hermes/executor.py`. Remove contract freeze marker. |
| 2 | Remove Platform Dispatch from Orchestrator persona prompt. Orchestrator returns to free-form routing. |
| 3 | Remove ContextStrategy integration from Dispatch. Vault returns to manual persona-initiated lookup. |
| 4 | Remove MemoryOrchestrator integration. Memory returns to Hermes-managed behavior. |
| 5 | Remove KnowledgeResolver integration. Web pre-search disabled. |
| 6 | Deregister telemetry callbacks. Telemetry store remains (read-only). |
| 7 | Stop benchmark runner. Results remain (read-only). |
| 8 | Stop Platform API Gateway. Caddy routes return to Hermes-only. |

### System-Wide Rollback

At any point, the entire Platform layer can be disabled by:

1. Stop Platform processes (API Gateway, if running)
2. Restore Orchestrator persona to pre-migration prompt (free-form routing)
3. Hermes operates exactly as it does today — all chat platforms, all personas, all tools

**The system always falls back to current behavior.** Migration is additive, not transformative.

### Rollback Triggers

Rollback should be considered if:

- Classification accuracy drops below 80% (measured by Phase 7 benchmarks)
- End-to-end latency increases by more than 2 seconds (measured by Phase 6 telemetry)
- Any persona produces worse results than pre-migration (measured by Phase 7 benchmarks)
- Hermes upstream update breaks the Adapter, and fixing the Adapter takes longer than 24 hours

---

## 10. Governance

This specification is governed by Hermes Architecture Governance v1.0.

**Lifecycle state:** Draft → Published (on commit) → Depended Upon (when `adapters/hermes/executor.py` imports ExecutionPlan) → Frozen.

**Amendments:** Require a full architecture review. Minor changes (adding a field to ExecutionPlan) follow minor version bump. Major changes (changing the boundary between Platform and Runtime) require a new specification.

**Canonical location:** `docs/specifications/platform-migration-v1.md`

**Depends on:**
- Architecture Decision — Platform owns intelligence, Hermes Runtime owns execution (frozen)

**Depended on by:**
- (none yet — will be depended on by Phase 1 implementation)
