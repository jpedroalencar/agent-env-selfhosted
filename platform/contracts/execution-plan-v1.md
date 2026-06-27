# ExecutionPlan v1.0 — Architectural Contract

---

## Why This Subsystem Exists

The ExecutionPlan is the single contract between Platform intelligence and Hermes Runtime execution. The Platform decides what to do; Hermes executes it mechanically. Without a structured plan, strategy leaks into execution prompts, making routing, context assembly, and memory decisions invisible and untestable.

---

## What It Owns

| ID | Responsibility |
|----|---------------|
| R1 | Declare which persona profile executes the task |
| R2 | Declare which skills to preload before execution |
| R3 | Declare which memory tier to activate for this task |
| R4 | Declare which knowledge providers to query, in priority order |
| R5 | Carry pre-assembled context as a single string block |
| R6 | Declare execution parameters: max iterations, timeout, model override |
| R7 | Declare validation criteria the Platform applies post-execution |
| R8 | Declare expected output format for downstream validation |
| R9 | Reject invalid plans before Hermes is invoked |

---

## What It Refuses to Own

| Non-Responsibility | Belongs To |
|--------------------|-----------|
| Never classify intent | Platform Dispatch (classifier) |
| Never resolve which skills to load for a given intent | Platform Dispatch (routing) |
| Never query knowledge providers | Platform Knowledge Resolver |
| Never assemble context blocks | Platform Context Strategy |
| Never decide memory tier strategy | Platform Memory Orchestrator |
| Never execute model calls or tool dispatch | Hermes Runtime |
| Never validate execution results | Platform Response Handler |
| Never contain implementation details of any subsystem | Respective subsystem contracts |

---

## Inputs (Conceptual)

- **User message** — the raw text from the user
- **Session context** — platform, user ID, profile, conversation ID, locale
- **Intent classification** — the classified intent (research, financial, code, ops, casual, multi-step)
- **Memory strategy** — which tiers to read, which tier to write, which tiers to wipe
- **Knowledge results** — resolved knowledge provider outputs with freshness and relevance scores
- **Context blocks** — assembled context with priority ordering and token budgets
- **Routing rules** — intent-to-profile mappings from Platform configuration

---

## Outputs (Conceptual)

- **ExecutionPlan** — a validated, complete plan ready for the Hermes Adapter to translate

---

## Architectural Invariants

| Invariant | Rationale |
|-----------|----------|
| **A plan is never executed without validation** | An invalid plan (missing profile, conflicting parameters) must be rejected before reaching Hermes. The Adapter rejects, the Platform handles the error. |
| **The plan carries WHAT, never HOW** | The plan says "use the financial-analyst profile with skills X and Y." It never says "call run_conversation with these args" — that's the Adapter's job. |
| **The plan is idempotent to produce** | Given the same input (message + session + config), dispatch produces the same plan. Classification is deterministic. |
| **preloaded_context is append-only from the Platform** | Hermes may add context mechanically (environment hints, tool guidance) but never removes or reinterprets Platform-provided context. |
| **The plan never contains model-specific formatting** | The plan is provider-agnostic. The Adapter handles provider-specific translation. |
| **No runtime state leaks into the plan** | The plan describes intent and strategy. It does not carry conversation history, tool results, or streaming state. Those are Hermes Runtime concerns. |

---

## Dependencies

**Depends on:**
- Platform Dispatch — provides intent classification and routing
- Platform Context Strategy — provides assembled context blocks
- Platform Memory Orchestrator — provides memory tier strategy
- Platform Knowledge Resolver — provides resolved knowledge results
- Platform Configuration (`config/routing.yaml`) — provides routing rules

**Depended on by:**
- Hermes Adapter (`adapters/hermes/executor.py`) — translates ExecutionPlan into Hermes parameters
- Platform Response Handler — reads validation_criteria and expected_output_format

---

## Future Boundaries

| Feature | Rightful Home | Why Not Here |
|---------|--------------|--------------|
| Streaming configuration | Hermes Adapter | The plan declares WHAT; streaming mechanics are HOW |
| Per-provider model selection | Hermes Adapter | The plan may override the model, but provider routing is adapter concern |
| Conversation history injection | Hermes Runtime | The plan is pre-execution; history is managed by the agent loop |
| Error recovery strategy | Platform Response Handler | Post-execution concern |
| Token budget allocation per context block | Platform Context Strategy | The plan carries assembled context; budget allocation is assembly concern |

---

**Contract version:** 1.0
**Amendments require:** A future architecture review explicitly referencing this contract by version number.
