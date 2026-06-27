# Runtime Context Controller v1.0 — Architectural Contract

---

## Why This Subsystem Exists

During execution, context changes in ways the Platform cannot predict: token thresholds are crossed, tool output overflows, the user sends mid-turn steering, the model or provider changes mid-session. Someone must decide what to do right now, inside the agent loop, without pausing execution. The Runtime Context Controller is that someone. It makes every tactical context decision during execution, and exactly zero strategic ones.

---

## What It Owns

| ID | Responsibility |
|----|---------------|
| R1 | Decide when context compression fires — based on token thresholds, not Platform strategy |
| R2 | Decide what to compress — which messages to summarize, which to protect as tail context |
| R3 | Decide whether to rebuild the system prompt mid-session — triggered by model or provider change |
| R4 | Inject mid-turn steering messages into the correct position in the message list |
| R5 | Handle tool output that exceeds context limits — truncate, retry, or inject continuation prompts |
| R6 | Track token usage per-response and per-session — prompt, completion, total, cache hit rate |
| R7 | Decide whether to drop low-priority system prompt blocks when token pressure is extreme |
| R8 | Report current context state to the Platform (via telemetry callbacks) — never to the Platform strategy layer |
| R9 | Expand @references found in tool output or mid-turn messages — mechanical string replacement |

---

## What It Refuses to Own

| Non-Responsibility | Belongs To |
|--------------------|-----------|
| Never decide which persona profile executes the task | Platform Dispatch |
| Never decide which skills to preload | Platform Context Strategy |
| Never decide which memory tier to activate | Platform Memory Orchestrator |
| Never decide which knowledge providers to query | Platform Knowledge Resolver |
| Never assemble the initial preloaded context | Platform Context Strategy |
| Never decide whether to persist memory after the turn | Platform Memory Orchestrator |
| Never classify user intent | Platform Dispatch |
| Never validate execution results | Platform Response Handler |
| Never select the model or provider for a task | Platform Dispatch (model_override in ExecutionPlan) |
| Never change the compression strategy (threshold ratio, target ratio, algorithm) | Hermes configuration (`config.yaml`) — this is operational config, not a per-turn decision |
| Never interpret the semantic content of tool output | The model does that; the Controller only handles mechanical overflow |
| Never decide what the system prompt says | Platform Context Strategy (initial) + Hermes `prompt_builder.py` (mechanical assembly) |

---

## Inputs (Conceptual)

- **ExecutionPlan** — the Platform's pre-execution strategy (profile, skills, memory tier, preloaded_context, max_iterations, timeout)
- **Active message list** — the current conversation messages being sent to the model
- **Token usage** — prompt_tokens, completion_tokens, total_tokens from the most recent API response
- **Model context length** — the current model's maximum context window
- **Compression configuration** — threshold_percent, target_ratio, max_compression_attempts from Hermes config
- **Mid-turn steering queue** — pending steer messages from the user
- **Tool output** — raw tool result about to be injected into context
- **Active system prompt** — the currently cached system prompt string

---

## Outputs (Conceptual)

- **Compression decision** — compress now, skip, or halt (cannot compress further)
- **Compressed message list** — the message list after summarization, with tail protection applied
- **Rebuilt system prompt** — a fresh system prompt when the cached one is invalidated
- **Injected steer message** — the steer text placed at the correct position in the message list
- **Truncated tool output** — tool result with overflow handled (truncation marker, retry request, or continuation prompt)
- **Token state** — updated prompt_tokens, completion_tokens, total_tokens, session accumulators
- **Context state report** — current token pressure, compression status, tail budget remaining (for telemetry)

---

## Architectural Invariants

| Invariant | Rationale |
|-----------|----------|
| **The ExecutionPlan is never modified** | The Controller works within the Platform's plan. It may compress, truncate, or reorder within the plan's boundaries, but it never changes the profile, skills, memory tier, or knowledge provider selections. Violating this would mean Runtime overriding Platform strategy. |
| **Compression is mechanical, not semantic** | The Controller triggers compression based on token thresholds — a number. It does not evaluate whether the conversation "needs" compression. That's a Platform concern. The Controller just does it when the math says to. |
| **Platform context is never dropped before Hermes context** | If token pressure forces dropping system prompt blocks, the Controller drops mechanical guidance (tool-use enforcement, environment hints) before touching Platform-provided context (preloaded_context). Platform intelligence is more valuable than Hermes boilerplate. |
| **Steer injection is always at the earliest safe position** | A mid-turn steer must reach the model on the next API call, not after the next tool batch. The Controller drains the steer queue before every API call and injects at the tail of the most recent tool result message — the earliest position that preserves role alternation. |
| **Compression must make material progress or stop** | If compression reduces token count by less than 5%, the Controller halts further attempts. This prevents infinite compression loops when context is already minimal. |
| **The Controller never calls an LLM for its own decisions** | All Controller decisions are deterministic: thresholds, counts, string matching. No model inference. If a decision requires intelligence, it belongs to the Platform. |
| **Tool output handling never alters semantic content** | The Controller truncates, marks, or requests retry — it never summarizes, paraphrases, or interprets tool output. Content interpretation belongs to the model. |

---

## Dependencies

**Depends on:**
- ExecutionPlan — provides the strategic boundaries the Controller works within
- Hermes `context_engine.py` — provides the compression abstraction (threshold tracking, `should_compress`, `compress`)
- Hermes `context_references.py` — provides @references expansion
- Hermes configuration — provides compression thresholds, max attempts, target ratios
- Hermes telemetry callbacks — provides the channel for context state reporting

**Depended on by:**
- Hermes agent loop (`conversation_loop.py`) — calls the Controller at every tactical decision point
- Platform Telemetry — receives context state reports for observability

---

## Future Boundaries

| Feature | Rightful Home | Why Not Here |
|---------|--------------|--------------|
| Adaptive compression thresholds that learn from usage patterns | Platform Telemetry → Platform Context Strategy | Learning from execution data is intelligence. The Controller executes fixed thresholds. |
| Content-aware compression (summarize financial data differently from code) | Platform Context Strategy | Deciding HOW to summarize is strategy. The Controller only decides WHEN. |
| Proactive context preloading based on predicted tool calls | Platform Context Strategy | Prediction is intelligence. The Controller reacts to what happened, not what might happen. |
| Per-persona compression profiles (research keeps more tail than casual chat) | Platform Context Strategy | Persona-specific behavior is strategy. |
| Dropping Platform context blocks to make room | Platform Context Strategy | The Controller may drop mechanical blocks; only the Platform can decide to drop its own content. |

---

**Contract version:** 1.0
**Amendments require:** A future architecture review explicitly referencing this contract by version number.
