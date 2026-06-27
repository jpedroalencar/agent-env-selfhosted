# Platform Architecture

**Architecture v3.0 (frozen).** This document describes the implemented architecture.

---

## 1. Architecture Overview

The Agent Platform is an intelligent orchestration layer that sits above Hermes Runtime. It receives user requests, determines what to do, assembles context, builds prompts, and delegates execution to Hermes.

```
┌─────────────────────────────────────────┐
│              PLATFORM                    │
│         (agent-env-selfhosted)           │
│                                         │
│  Owns: intelligence, strategy, content  │
│                                         │
│  • Gateway (entry point)               │
│  • Context Planner (parse + classify)  │
│  • Context System (assemble)           │
│  • Knowledge Providers (config, memory)│
│  • Prompt Builder (format)             │
│  • Telemetry (planned)                 │
│  • Benchmarks (planned)                │
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
│         (external dependency)           │
│                                         │
│  Owns: execution, mechanics, transport  │
│                                         │
│  • Model execution                     │
│  • Tool dispatch                       │
│  • Streaming                           │
│  • Chat platform adapters (Telegram)   │
└─────────────────────────────────────────┘
```

**Platform owns intelligence. Hermes Runtime owns execution.** The Platform decides what to do; Hermes executes it mechanically. The Adapter is the single integration point.

---

## 2. Deterministic Request Pipeline

Every user request flows through a fixed 9-stage pipeline. No stage calls an LLM except the final model execution.

```
User Request
    │
    ▼
┌──────────┐
│  Parser  │  pilot/dispatch/_parser.py
└────┬─────┘  Extracts: question markers, imperative verbs, URLs,
     │        file paths, code terms, Hermes terms, skill mentions.
     │        Pure regex. No NLP. No I/O.
     ▼
┌───────────┐
│ Classifier│  pilot/dispatch/_classifier.py
└─────┬─────┘  Maps ParsedRequest → RequestShape.
      │       8 shapes: CODE_CHANGE, CODE_QUESTION, RESEARCH,
      │       CASUAL_CONVERSATION, MULTI_STEP_WORKFLOW,
      │       CONFIG_CHANGE, HERMES_SELF_SERVICE, AMBIGUOUS.
      │       Decision tree. Deterministic.
      ▼
┌──────────────┐
│ IntentMapper │  pilot/dispatch/intent_mapper.py
└──────┬───────┘  Maps RequestShape → Platform intent.
       │         Lookup table. 8 shapes → 6 intents.
       ▼
┌──────────────┐
│ConfigProvider│  pilot/config_provider.py
└──────┬───────┘  Reads config/routing.yaml.
       │         15 intents mapped to 5 profiles.
       │         Returns RoutingRule: profile, skills,
       │         memory_tier, knowledge_providers.
       ▼
┌──────────────────┐
│  ExecutionPlan   │  pilot/dispatch/plan.py
└────────┬─────────┘  Frozen contract. Carries profile, skills,
         │            memory tier, knowledge providers.
         │            Validated before execution.
         ▼
┌──────────────────────┐
│  Knowledge Providers │  pilot/knowledge/providers/
└──────────┬───────────┘  ConfigProvider + MemoryProvider.
           │              Each produces KnowledgeArtifact.
           │              Same contract: produce_artifact(intent).
           ▼
┌─────────────────┐
│  Context System │  pilot/context/system.py
└────────┬────────┘  Assembles artifacts into context string.
         │           Labeled markdown blocks.
         │           Provider-agnostic.
         ▼
┌─────────────────┐
│  Prompt Builder │  pilot/prompt/builder.py
└────────┬────────┘  Formats system prompt + context + question.
         │           Pure template. No decisions.
         ▼
┌───────────────┐
│  Hermes Adapter│  adapters/hermes/model.py
└───────┬───────┘  Calls DeepSeek via OpenAI SDK.
        │          Receives prompt string only.
        │          No ExecutionPlan. No routing.
        ▼
    Model Response
```

---

## 3. Platform Responsibilities

| Responsibility | Implementation | Status |
|---------------|---------------|--------|
| Request parsing | `pilot/dispatch/_parser.py` (273 lines) | ✅ |
| Request classification | `pilot/dispatch/_classifier.py` (198 lines) | ✅ |
| Intent mapping | `pilot/dispatch/intent_mapper.py` (39 lines) | ✅ |
| Configuration | `pilot/config_provider.py` | ✅ |
| Execution planning | `pilot/dispatch/plan.py` | ✅ |
| Knowledge provision | `pilot/knowledge/providers/` (config, memory) | ✅ |
| Context assembly | `pilot/context/system.py` | ✅ |
| Prompt formatting | `pilot/prompt/builder.py` | ✅ |
| Telemetry | — | ⬜ Phase 6 |
| Benchmarks | — | ⬜ Phase 7 |
| HTTP Gateway | — | ⬜ Phase 8 |

---

## 4. Runtime Responsibilities

| Responsibility | Implementation | Status |
|---------------|---------------|--------|
| Model execution | `adapters/hermes/model.py` (DeepSeek) | ✅ |
| Tool dispatch | Hermes Runtime (external) | ✅ |
| Streaming | Hermes Runtime (external) | ✅ |
| Chat adapters (Telegram) | Hermes Runtime (external) | ✅ |
| Context compression | Hermes Runtime (external) | ✅ |
| Session persistence | Hermes Runtime (external) | ✅ |

---

## 5. Provider Model

KnowledgeProviders follow a single contract:

```python
def produce_artifact(intent: str) -> KnowledgeArtifact
```

Two providers are implemented:

| Provider | Source | Reads |
|----------|--------|-------|
| ConfigProvider | `config/routing.yaml` | Routing rules |
| MemoryProvider | `~/.hermes/memories/MEMORY.md` | Agent memory |

Providers are called in order. The Context System receives a list of artifacts and formats them — it does not know or care which providers produced them.

Future providers: Vault (`artifacts/`), Web (search API).

---

## 6. Repository Organization

```
agent-env-selfhosted/
├── pilot/              # Platform intelligence layer
│   ├── contracts/      # Frozen architectural contracts
│   ├── dispatch/       # Parser, classifier, intent mapper, ExecutionPlan
│   ├── context/        # Context assembly
│   ├── knowledge/      # Knowledge provider framework
│   │   └── providers/  # ConfigProvider, MemoryProvider
│   ├── prompt/         # Prompt builder
│   └── gateway.py      # Request entry point
├── adapters/           # Hermes Runtime adapter
│   └── hermes/         # Model adapter, (future) config bridge
├── config/             # Platform configuration (routing.yaml)
├── agent/              # Persona definitions, memory schemas
├── artifacts/          # Knowledge Vault
├── docs/               # Documentation
│   └── specifications/ # Architecture specifications
├── diagrams/           # Architecture diagrams
├── log/                # Engineering journal
├── scripts/            # Automation (backup, vault)
├── tests/              # Test suite (60 tests)
├── apps/               # Application registry
├── infra/              # Infrastructure config (future)
├── workspaces/         # Temporary (gitignored)
└── .hermes/            # Operational logs (gitignored)
```

---

## 7. Implementation Status

| Component | Tests | Status |
|-----------|-------|--------|
| ConfigProvider | 32 | ✅ Complete |
| Parser + Classifier + Mapper | 28 | ✅ Complete |
| ExecutionPlan validation | — | ✅ Complete |
| KnowledgeProviders (config, memory) | — | ✅ Complete |
| Context System | — | ✅ Complete |
| Prompt Builder | — | ✅ Complete |
| Gateway pipeline | — | ✅ Complete |
| **Total** | **60** | **All passing** |

---

## 8. Deployment Architecture

The Platform runs inside an LXC container on Oracle Cloud VPS:

```
Oracle Cloud VPS (Ubuntu 24.04, ARM64)
└── LXD Container (Debian 12)
    ├── Hermes Agent v0.17.0 (Runtime)
    │   ├── DeepSeek API (primary)
    │   ├── OpenRouter (fallback)
    │   └── Telegram Gateway (chat interface)
    ├── Platform (this repository)
    │   ├── ConfigProvider
    │   ├── Dispatch pipeline
    │   └── Knowledge providers
    └── Knowledge Vault (artifacts/)
```

The Platform is NOT a separate service. It is a Python package imported by Hermes during request processing. The Platform and Hermes Runtime coexist in the same container but are architecturally isolated by the Adapter boundary.
