# Runtime Context Controller — Forbidden Decisions

> **Status:** Appendix to Runtime Context Controller v1.0
> **Purpose:** Enforceable reference for code review. A PR that adds any of these decisions to the Controller is an architectural violation.

---

Every decision below is forbidden to the Runtime Context Controller.
Each names its rightful owner.

---

## Strategic Context Decisions (Forbidden)

| # | Forbidden Decision | Rightful Owner | Why It's Forbidden |
|---|-------------------|---------------|--------------------|
| D1 | Choosing which persona profile to use | Platform Dispatch (`config/routing.yaml`) | The Controller executes within a profile chosen by the Platform. Picking a different profile mid-execution would reroute the user's intent without Platform awareness. |
| D2 | Selecting which skills to preload | Platform Context Strategy | Skills define the agent's capabilities for a task. Adding or removing skills mid-execution changes what the agent can do — a strategic decision. |
| D3 | Activating a different memory tier | Platform Memory Orchestrator | Whether to use persistent, working, or no memory is a Platform strategy decision. The Controller reads from the tier specified in the ExecutionPlan. |
| D4 | Choosing which knowledge providers to query | Platform Knowledge Resolver | Which providers to query and in what order is Platform strategy. The Controller works with whatever knowledge was preloaded. |
| D5 | Assembling the initial preloaded context | Platform Context Strategy | The Platform assembles context before execution. The Controller only manages what happens to that context during execution. |
| D6 | Deciding whether to persist memory post-turn | Platform Memory Orchestrator | Writing to persistent memory is a Platform decision. The Controller may report that memory was used, but never writes it. |
| D7 | Dropping Platform-provided context blocks | Platform Context Strategy | Under token pressure, the Controller may drop mechanical blocks (tool guidance, environment hints). It must never drop context the Platform injected. |
| D8 | Changing the compression strategy | Hermes configuration (`context.compression` in `config.yaml`) | Threshold percent, target ratio, and algorithm are operational config, not per-turn decisions. |

---

## Intent & Routing Decisions (Forbidden)

| # | Forbidden Decision | Rightful Owner | Why It's Forbidden |
|---|-------------------|---------------|--------------------|
| D9 | Classifying user intent | Platform Dispatch (`classifier.py`) | The Controller operates after classification. Reclassifying mid-execution would override the Platform's routing decision. |
| D10 | Rerouting to a different profile mid-task | Platform Dispatch | A task belongs to the profile the Platform assigned. The Controller cannot transfer it. |
| D11 | Deciding to delegate a subtask | Platform Dispatch | Delegation is a Platform orchestration decision. The Controller manages context for the current task only. |

---

## Model & Provider Decisions (Forbidden)

| # | Forbidden Decision | Rightful Owner | Why It's Forbidden |
|---|-------------------|---------------|--------------------|
| D12 | Selecting a different model mid-execution | Platform Dispatch (`model_override` in ExecutionPlan) | Model selection is a Platform decision. The Controller may trigger a system prompt rebuild if the model changes during failover, but it never initiates the change. |
| D13 | Switching to a different provider | Hermes fallback chain (operational) + Platform Dispatch (strategic) | Operational failover is Hermes Runtime. Strategic provider selection is Platform. The Controller does neither — it reacts to provider changes that already happened. |

---

## Content & Validation Decisions (Forbidden)

| # | Forbidden Decision | Rightful Owner | Why It's Forbidden |
|---|-------------------|---------------|--------------------|
| D14 | Validating execution results | Platform Response Handler | The Controller manages context during execution. It does not inspect, score, or validate the final output. |
| D15 | Interpreting tool output semantically | The model | The Controller handles mechanical overflow (truncation, retry). It never reads tool output and decides what it means. |
| D16 | Deciding what the system prompt says | Platform Context Strategy (initial content) + Hermes `prompt_builder.py` (mechanical assembly) | The Controller may trigger a rebuild, but never changes the content of the system prompt. |
| D17 | Summarizing tool output | The model (or Platform Context Strategy, if pre-planned) | The Controller truncates — it never paraphrases. Summarization is intelligence. |

---

## Observability Decisions (Forbidden)

| # | Forbidden Decision | Rightful Owner | Why It's Forbidden |
|---|-------------------|---------------|--------------------|
| D18 | Deciding what telemetry to collect | Platform Telemetry | The Controller reports context state through callbacks. The Platform decides what to record and how to analyze it. |
| D19 | Triggering alerts based on context pressure | Platform Telemetry | The Controller reports token pressure. The Platform decides whether that pressure warrants an alert. |

---

## Enforcement

A code review finding any of these decisions inside the Runtime Context Controller is an architectural violation. The fix is:

1. Move the decision to its rightful owner (see table)
2. The Controller receives the decision as input (via ExecutionPlan or config), never makes it

The Controller is a **mechanical executor of context tactics**. If it makes a decision that could have been different under different Platform strategy, that decision belongs to the Platform.
