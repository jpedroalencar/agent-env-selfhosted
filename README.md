# Agent Platform

A self-hosted AI agent platform that runs on Oracle Cloud VPS with LXC containers. The Platform owns intelligence — classifying requests, assembling context, selecting knowledge providers. Hermes Runtime handles execution — model calls, tool dispatch, streaming.

> **Disclaimer:** This repository documents a platform in active development. Items marked ⬜ are planned, not implemented.

---

## Architecture

The Platform is an intelligent orchestration layer. It receives user requests, determines what to do, assembles context, builds prompts, and delegates execution to Hermes Runtime.

```
User Request
    │
    ▼
┌──────────────────────────────────────────┐
│  PLATFORM (agent-env-selfhosted)         │
│                                          │
│  Parser → Classifier → IntentMapper      │
│     → ConfigProvider → ExecutionPlan     │
│     → KnowledgeProviders                 │
│     → Context Assembly → Prompt Builder  │
│                                          │
│  Owns: intelligence, strategy, content   │
└──────────────────┬───────────────────────┘
                   │  ExecutionPlan
                   ▼
┌──────────────────────────────────────────┐
│  HERMES RUNTIME (external dependency)    │
│                                          │
│  Model calls, tool dispatch, streaming,  │
│  chat platform adapters (Telegram)       │
│                                          │
│  Owns: execution, mechanics, transport   │
└──────────────────────────────────────────┘
```

**Platform owns intelligence. Hermes owns execution.** The Platform decides; Hermes executes. See [docs/platform-architecture.md](docs/platform-architecture.md) for the full pipeline.

---

## Current Implementation

### ✅ Implemented

| Component | Description |
|-----------|-------------|
| **Context Planner** | Parse user messages, classify intent (8 request types), map to Platform profiles. Migrated from Hermes. |
| **ConfigProvider** | Declarative routing: 15 intents → 5 profiles. Reads `config/routing.yaml`. |
| **ExecutionPlan** | Frozen contract carrying profile, skills, memory tier, knowledge providers. Validated before execution. |
| **Knowledge Providers** | ConfigProvider and MemoryProvider implement the frozen KnowledgeProvider contract and demonstrate provider-independent context assembly. |
| **Context System** | Assembles provider artifacts into labeled context blocks. Provider-agnostic. |
| **Prompt Builder** | Formats system prompt + context + question. Pure template. |
| **Knowledge Vault** | Curated knowledge artifacts consumed by Knowledge Providers during context assembly. 10 artifacts. Automated lookup, freshness, registration. |
| **Backup & Recovery** | LXD snapshot backup with retention, restore, host validation evidence. |
| **Telegram Interface** | Primary chat via Hermes Telegram gateway. Multi-session, multi-thread. |
| **Multi-Provider LLM** | DeepSeek (primary) with fallback to OpenRouter. |
| **Git Identity** | Author/Committer separation enforced by `scripts/git-commit.sh`. |

### ⬜ Planned

| Component | Phase |
|-----------|-------|
| Vault + Web Knowledge Providers | 5 |
| Telemetry (event collection, reporting) | 6 |
| Benchmark suites | 7 |
| HTTP Gateway (Caddy, OAuth, API) | 8 |
| Memory Orchestration | 4 |

---

## Repository Structure

```
├── pilot/              # Platform intelligence layer
│   ├── contracts/      # Frozen architectural contracts
│   ├── dispatch/       # Parser, classifier, intent mapper, ExecutionPlan
│   ├── context/        # Context assembly
│   ├── knowledge/      # Knowledge providers (config, memory)
│   ├── prompt/         # Prompt builder
│   └── gateway.py      # Request entry point
├── adapters/           # Hermes Runtime adapter
│   └── hermes/         # Model adapter, (future) config bridge
├── config/             # Platform configuration (routing.yaml)
├── agent/              # Persona definitions, memory schemas
├── artifacts/          # Knowledge Vault
├── docs/               # Documentation
│   ├── specifications/ # Architecture specifications
│   └── platform-architecture.md
├── diagrams/           # Architecture diagrams
├── log/                # Engineering journal
├── scripts/            # Automation (backup, vault, git commit wrapper)
├── tests/              # Test suite (60 tests)
├── apps/               # Application registry
├── infra/              # Infrastructure config (future)
├── workspaces/         # Temporary (gitignored)
└── .hermes/            # Operational logs (gitignored)
```

---

## Deployment

```
Oracle Cloud VPS (Ubuntu 24.04, ARM64)
└── LXD Container (Debian 12)
    ├── Hermes Agent v0.17.0 (Runtime)
    │   ├── DeepSeek API (primary)
    │   ├── OpenRouter (fallback)
    │   └── Telegram Gateway
    ├── Platform (this repository)
    └── Knowledge Vault
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [Platform Architecture](docs/platform-architecture.md) | Full pipeline, responsibilities, provider model |
| [Architecture v3.0](docs/architecture.md) | System design, topology, persona architecture |
| [Configuration](docs/configuration.md) | Hermes config, providers, conventions |
| [Deployment](docs/deployment.md) | VPS → LXC → Hermes → GitHub |
| [Operations](docs/operations.md) | Infrastructure and persona-level procedures |
| [Security](docs/security.md) | Access control, isolation, network |
| [Backup & Recovery](docs/backup-recovery.md) | Snapshot backup, restore, evidence |
| [Knowledge Vault](docs/workflows/knowledge-vault.md) | Retrieval-before-research workflow |
| [Git Identity](docs/GIT-IDENTITY.md) | Author/Committer policy |
| [Specifications](docs/specifications/) | Migration plans, conformance audits |

---

## Design Decisions

- **Platform/Runtime separation.** The Platform owns strategy; Hermes handles execution. They communicate through a single contract (ExecutionPlan).
- **LXC over Docker.** Hermes needs a real Linux environment. LXD provides filesystem semantics, snapshots, and strong isolation without Docker's abstraction overhead.
- **ARM-based VPS.** Oracle Cloud Ampere A1 free tier. Agent workloads are network-bound, not CPU-bound.
- **Declarative routing.** Intent → profile mappings in `config/routing.yaml`. No rule engine. No dependency resolver. One YAML file.
- **Minimal abstractions.** Two providers → explicit wiring. Registry at 3+. Every abstraction earns its place.

---

## Core Principles

- Deterministic planning before reasoning
- Dynamic context engineering
- Provider-based knowledge access
- Stable public contracts
- Runtime independence

---

## Philosophy

Agent Platform is a deterministic orchestration platform that prepares the smallest useful information for a reasoning runtime. Strategic decisions are made before model invocation, allowing the runtime to focus solely on reasoning rather than context discovery.

