# Research Analyst — Execution Sequence

Mermaid sequence diagram showing the intended Research Analyst workflow. Each stage includes a status classification to distinguish implemented from planned functionality.

**Canonical source:** `docs/workflows/research-pipeline.md`

---

## Sequence Diagram

```mermaid
sequenceDiagram
    actor User as Telegram User
    participant Telegram as Telegram Bot API
    participant Hermes as Hermes Agent
    participant Orchestrator as Orchestrator (Routing)
    participant RA as Research Analyst
    participant DeepSeek as DeepSeek API
    participant Content as Content Storage<br/>~/.hermes/content/
    participant Git as GitHub Repository

    Note over User,Git: Stage A — Request Reception [IMPLEMENTED]
    User->>Telegram: Send research request
    Telegram->>Hermes: Webhook / poll (Bot Token auth)
    Hermes->>Orchestrator: Parse intent & extract scope

    Note over Hermes,Orchestrator: Stage B — Routing [IMPLEMENTED]
    Orchestrator->>RA: Delegate with research brief

    Note over RA,DeepSeek: Stage C — Research Execution [IMPLEMENTED]
    RA->>DeepSeek: Plan & execute research (LLM inference)
    DeepSeek-->>RA: Response with findings

    Note over RA: Stage D — Output Structuring [PARTIALLY IMPLEMENTED]
    RA->>RA: Structure into research brief<br/>(Key Findings, Conclusions, Gaps, Sources)

    Note over RA,Content: Stage E — Artifact Storage [PARTIALLY IMPLEMENTED]
    RA->>Content: Save to content/research-analyst/<br/>YYYY-MM-DD_short-title.md

    Note over Content,Git: Stage F — Repository Commit [PLANNED]
    Content->>Git: Commit artifact to<br/>agent-env-selfhosted repository

    Note over Hermes,User: Stage G — User Notification [IMPLEMENTED]
    Hermes-->>Telegram: Deliver result summary
    Telegram-->>User: Display response
```

---

## Stage Status Key

| Icon | Status | Meaning |
|------|--------|---------|
| ✅ | **Implemented** | Component is operational and actively used. No additional work required. |
| 🟡 | **Partially Implemented** | Infrastructure exists (directories, naming conventions, tooling) but the full automated pipeline has not been exercised. Manual intervention or additional configuration may be required. |
| ⬜ | **Planned** | Component is designed and documented but not yet built. Cannot be used without implementation. |

---

## Stage-by-Stage Status

| Stage | Label | Status | Current Reality |
|-------|-------|--------|-----------------|
| A | Request Reception | ✅ **Implemented** | Telegram gateway is running (PID 15397), actively connected to Telegram API (3 established connections). Accepts and processes user messages. |
| B | Routing | ✅ **Implemented** | Orchestrator routing logic exists. Research Analyst SKILL.md is loaded and delegatable via `delegate_task`. |
| C | Research Execution | ✅ **Implemented** | Hermes Agent LLM provider (DeepSeek) is operational. OpenRouter fallback is configured. The agent can execute research tasks with web search and browser tools. |
| D | Output Structuring | 🟡 **Partially Implemented** | The persona definition documents the output structure (Key Findings, Conclusions, Gaps, Sources). The RA can produce structured responses in chat. However, no research artifacts have been saved to disk as standalone files. |
| E | Artifact Storage | 🟡 **Partially Implemented** | Content directory structure exists at `~/.hermes/content/research-analyst/` with documented naming convention (`YYYY-MM-DD_short-kebab-title.md`). The pipeline step (save → summarize → reference in chat) has been designed but never exercised — 0 files exist in any content directory. |
| F | Repository Commit | ⬜ **Planned** | The concept of committing final research artifacts to the repository is documented in the persona definition (Collaboration Rules → OM updates project memory). No automated commit pipeline exists. Manual git operations are possible but require explicit operator direction. |
| G | User Notification | ✅ **Implemented** | Hermes sends response messages to Telegram. The gateway is actively delivering responses. |
