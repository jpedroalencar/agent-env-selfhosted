# Research Analyst — Research Pipeline

Runbook documenting the Research Analyst workflow, component status, routing logic, artifact conventions, and separation between current and planned capabilities.

**Related files:**
- `diagrams/sequence-research.md` — Mermaid sequence diagram (visual companion to this document)
- `agent/personas/research-analyst.md` — Persona definition (purpose, boundaries, memory scope)
- `docs/architecture.md` — System architecture and persona architecture
- `docs/configuration.md` — Content storage conventions and persona storage layout

---

## 1. Overview

The Research Analyst pipeline transforms a natural-language research request into a structured, citable research artifact. The workflow spans message reception, persona routing, LLM-assisted research execution, artifact storage, optional repository commitment, and user delivery.

The pipeline is designed incrementally. Implementation status decreases as workflow stages progress downstream — reception and execution are fully operational; storage and commitment are partially or not yet implemented.

---

## 2. Workflow Sequence

The following describes each stage of the diagram in `diagrams/sequence-research.md`, in execution order.

### Stage A — Request Reception [Implemented]

1. A user sends a message to the Telegram bot.
2. The Telegram Bot API delivers the message to the Hermes Gateway via long-polling or webhook (Hermes internal). Authentication uses the bot token.
3. The Hermes Agent receives the message and extracts the request payload. No preprocessing or intent classification is applied at this stage — the raw message text is passed to the agent context.

### Stage B — Routing [Implemented]

4. The Hermes Agent evaluates the message against the routing table (see §5 — Routing Logic). If the request matches the Research Analyst's domain, the agent loads the `research-analyst` skill via `skill_view(name='research-analyst')` and delegates the task via `delegate_task(context=skill_content, goal=<extracted brief>)`.
5. The Research Analyst persona activates with its full identity, rules, and memory.

### Stage C — Research Execution [Implemented]

6. The Research Analyst conducts research using the tools available to it: web search (`web_search`), web content extraction (`web_extract`), browser navigation (`browser_navigate`), and LLM-assisted synthesis via the configured provider (DeepSeek as primary, OpenRouter as fallback).
7. Findings are gathered, sources are evaluated, and information gaps are identified.
8. The Research Analyst prioritizes source quality: primary sources over secondary commentary, authoritative domains over general references, dated content over undated content.

### Stage D — Output Structuring [Partially Implemented]

9. Research findings are structured into a standard brief format:
   - Key Findings
   - Important Conclusions
   - Uncertainties and Gaps
   - Supporting Evidence (with source annotations)
10. **Current state:** This structuring happens within the chat conversation. The RA can produce well-formatted structured output in its response. However, no method exists to persist this structured output as a standalone file without explicit operator intervention. The `delegate_task` mechanism returns a text summary, not a file handle.

### Stage E — Artifact Storage [Partially Implemented]

11. The structured brief is saved to `~/.hermes/content/research-analyst/YYYY-MM-DD_short-kebab-title.md` following the naming convention documented in `docs/configuration.md §5`.
12. **Current state:** The directory structure exists and the naming convention is documented. However, this step has never been exercised — 0 files exist across all content directories. The RA persona does not currently have an automated post-completion hook to save artifacts. Saving requires explicit scripting within the delegation task.

### Stage F — Repository Commit [Planned]

13. Final research artifacts are committed to the `agent-env-selfhosted` repository under `artifacts/` or `docs/` depending on the artifact type.
14. **Current state:** No automated commit pipeline exists. Manual `git add` + `git commit` + `git push` operations are possible but require explicit direction from the operator (John). The persona definition documents this pattern in the Collaboration Rules section but does not implement it.

### Stage G — User Notification [Implemented]

15. Research results are delivered back to the user via Telegram as a chat message.
16. If a content artifact was saved (Stage E), the response includes a one-line reference: `[RA → ~/.hermes/content/research-analyst/YYYY-MM-DD_title.md]`.
17. **Current state:** Stage 16 (file reference in response) is documented convention but has never been verified because no artifacts have been saved.

---

## 3. Component Status Matrix

| Component | Stage | Status | Evidence |
|-----------|-------|--------|----------|
| Telegram Bot API | A: Reception | ✅ **Implemented** | Gateway PID 15397 running. 3 established connections to `api.telegram.org:443`. Agent processes incoming messages. |
| Hermes Gateway | A: Reception | ✅ **Implemented** | Running as `python -m hermes_cli.main gateway run`. Accepts Telegram webhook/poll. |
| Hermes Agent | A-B: Reception & Routing | ✅ **Implemented** | Hermes v0.17.0 running. Orchestrator routing documented and operational. |
| Orchestrator Routing | B: Routing | ✅ **Implemented** | Routing table maintained in memory. `delegate_task` mechanism operational. Loads persona SKILL.md on delegation. |
| Research Analyst Skill | B: Activation | ✅ **Implemented** | SKILL.md present at `~/.hermes/skills/personas/research-analyst/SKILL.md`. Readiness status: available. |
| Research Analyst Workspace | B: Activation | ✅ **Implemented** | Directory exists at `~/.hermes/personas/research-analyst/workspace/`. Currently empty (0 files). |
| Research Analyst Memory | B: Activation | 🟡 **Partially Implemented** | Memory file exists at `~/.hermes/personas/research-analyst/memory.md`. Contains template structure only — all sections show "(none yet)". No completed research has been recorded. |
| DeepSeek API (Primary) | C: Execution | ✅ **Implemented** | Operational. Model: `deepseek-v4-flash`. Auth via API key. Fallback configured to OpenRouter. |
| OpenRouter API (Fallback) | C: Execution | ✅ **Implemented** | Operational. Model: `google/gemini-2.0-flash`. Response caching enabled (300s TTL). |
| Web Search Tool | C: Execution | ✅ **Implemented** | Toolset `web` enabled. Backend: DuckDuckGo (`web.backend: ddgs`). |
| Web Extraction Tool | C: Execution | ✅ **Implemented** | Toolset `web` enabled. Extracts page content as markdown. |
| Browser Tool | C: Execution | ✅ **Implemented** | Browser automation toolset enabled. Engine: auto. Support for complex page interaction. |
| Output Structuring | D: Output | 🟡 **Partially Implemented** | Output format documented in persona SKILL.md. RA can structure responses in chat. No persisted standalone artifact has been produced. |
| Content Directory | E: Storage | 🟡 **Partially Implemented** | `~/.hermes/content/research-analyst/` exists. Naming convention documented. 0 files present — never exercised. |
| Content Naming Convention | E: Storage | ✅ **Implemented** | Documented in `docs/configuration.md §5`: `YYYY-MM-DD_short-kebab-title.md`. Each persona writes to its own subdirectory only. |
| Artifact Commit to Repo | F: Commit | ⬜ **Planned** | Design documented in persona Collaboration Rules. No automated pipeline. Manual git operations possible with operator direction. |
| Telegram Response Delivery | G: Notification | ✅ **Implemented** | Hermes sends responses via the gateway. Messages are delivered to the originating chat/thread. |
| File Reference in Response | G: Notification | 🟡 **Partially Implemented** | Convention documented: `[Agent] → [Path]`. Never verified because no artifacts exist to reference. |

---

## 4. Trigger Conditions

The Research Analyst workflow is initiated by any of the following:

| Trigger Type | Example | Routing Action |
|-------------|---------|----------------|
| General research request | "Research the current state of LXD vs. Docker..." | Route to Research Analyst |
| Competitive analysis | "How does Tool X compare to Tool Y?" | Route to Research Analyst |
| Product evaluation | "Evaluate Obsidian vs. Notion for note-taking" | Route to Research Analyst |
| Legal/regulatory question | "What GDPR considerations apply?" | Route to Research Analyst |
| Academic literature search | "Find papers on LXC isolation techniques" | Route to Research Analyst |
| Slash command | `/research` | Route to Research Analyst directly |

**Non-triggers** (requests that are explicitly routed elsewhere):
- Financial data requests (e.g., "find P/E ratio") → Routed to Financial Analyst
- Code or implementation requests → Routed to Dev
- Documentation or planning requests → Routed to Operations Manager

---

## 5. Routing Logic

The Hermes Agent evaluates incoming requests against the routing table maintained by the Orchestrator persona.

### Confidence-Based Decision Tree

```
Request received
    ↓
Evaluate against routing table:
    ├── High confidence match (RA domain) → Auto-assign, no confirmation
    ├── Multiple relevant personas → Present labeled options (A/B/C)
    ├── Low confidence → Ask operator for direction
    └── Cross-domain → Orchestrator coordinates multiple personas
```

### Current Implementation

- **High-confidence routing** works automatically. The agent loads the persona skill and delegates.
- **Multi-persona options** work — the agent presents choices and routes based on selection.
- **Cross-domain coordination** works — the Orchestrator can delegate to multiple personas sequentially.
- **No routing metrics exist.** There is no dashboard, log, or counter tracking how often each persona is routed to, how long tasks take, or what percentage are high-confidence vs. low-confidence.
- **No routing persistence.** Routing decisions are not recorded to memory automatically. The decision tree exists in the agent's context but is not persisted between sessions.

---

## 6. Persona Responsibilities

### Research Analyst — Authority Boundaries

| Scope | Detail |
|-------|--------|
| **Owns** | Deep research, information gathering, source evaluation, competitive intelligence, product evaluations, regulatory research |
| **Does not own** | Investment recommendations, code implementation, infrastructure changes, platform documentation structure |
| **Cannot** | Make buy/sell/hold recommendations, deploy code, modify platform configuration, author platform-level documentation without Operations Manager review |

### Research Analyst — Output Requirements

Every research brief must contain:
1. Key Findings — What was discovered
2. Important Conclusions — What the findings mean
3. Uncertainties and Gaps — What is not known
4. Supporting Evidence — Sources with quality annotations

### Research Analyst — Collaboration Boundaries

| Partner | Interaction Pattern |
|---------|-------------------|
| **Financial Analyst** | RA gathers sector intelligence. FA incorporates into valuation models. RA accepts data-spec requests from FA. |
| **Dev** | RA evaluates tools and platforms. Dev implements based on findings. RA provides technical constraints. |
| **Operations Manager** | OM tracks coverage areas. RA reports completed threads. OM updates project memory. |

---

## 7. Artifact Generation Rules

### Storage Location

```
~/.hermes/content/
├── research-analyst/
│   ├── YYYY-MM-DD_short-kebab-title.md
│   └── ...
```

### Naming Convention

Pattern: `YYYY-MM-DD_short-kebab-title.md`

Examples:
- `2026-06-23_lxd-vs-docker-agent-workloads.md`
- `2026-06-23-gdpr-self-hosted-ai-agents.md`
- `2026-06-23-obsidian-vs-notion-vs-logseq.md`

Rules:
- Date prefix: ISO 8601 date (YYYY-MM-DD)
- Title: kebab-case, 3-8 words, descriptive
- Extension: `.md`
- Each persona writes to its own subdirectory only

### Artifact Structure

Each artifact file follows this structure:

```markdown
# <Title>

**Date:** YYYY-MM-DD
**Author:** Research Analyst
**Status:** draft | reviewed | archived

## Executive Summary

<2-3 sentence overview>

## Key Findings

- <Finding 1>
- <Finding 2>

## Conclusions

<What the findings mean>

## Uncertainties & Gaps

<What is not known or uncertain>

## Sources

| Source | Type | Quality | Date |
|--------|------|---------|------|
| url | primary/secondary | high/medium/low | YYYY-MM-DD |
```

### Repository Commit Expectations

- **Currently:** No artifacts have been committed to the repository. Content in `~/.hermes/content/` is gitignored.
- **Planned:** Final reviewed artifacts may be committed to `artifacts/` or `docs/` in the `agent-env-selfhosted` repository after Operations Manager review.
- **Constraint:** Only final artifacts after review may be committed. Raw research notes, intermediate drafts, and scratchpads remain in `~/.hermes/content/` and `~/.hermes/personas/*/workspace/` (both gitignored).

---

## 8. Memory Protection Boundary

The following must **never** be committed to the repository, regardless of storage implementation:

### Never Commit

| Category | Examples | Location |
|----------|----------|----------|
| Conversation history | Chat transcripts, session logs | Hermes session DB (gitignored) |
| Intermediate scratchpads | Working notes, partial drafts | Workspace dirs (gitignored) |
| Memory databases | `memory.db`, Chroma, Qdrant, vector stores | `.gitignore` blocks all |
| Embeddings | Vector embeddings, semantic indices | `.gitignore` blocks `embeddings/` |
| Runtime memory contents | MEMORY.md, USER.md, persona memories | `~/.hermes/memories/` (gitignored) |
| Raw API responses | Full web scrape results, API payloads | Not stored (summaries only) |
| Credentials | API keys, tokens, passwords | `.gitignore` blocks `secrets.env` |

### May Commit

| Category | Examples | Location |
|----------|----------|----------|
| Final research artifacts | Reviewed, structured briefs | `~/.hermes/content/` → `artifacts/` or `docs/` |
| Memory schemas | Template files, field definitions | `agent/memory/` |
| Persona definitions | SKILL.md, persona boundary docs | `agent/personas/` |
| Decision records | Build log entries, ADRs | `docs/build-log.md`, `agent/memory/` |
| Workflow documentation | Runbooks, sequence diagrams | `docs/workflows/` |

---

## 9. User Notification

### Current Implementation

- Research results are delivered as Telegram chat messages in the originating conversation thread.
- Hermes sends the complete response through the gateway.
- No structured notification format is enforced — the RA persona determines the response format based on the research brief structure.

### Documented Convention (Not Yet Verified)

When an artifact is saved to content storage, the response should include a one-line reference:

```
[RA → ~/.hermes/content/research-analyst/2026-06-23_topic-title.md]
```

This convention is documented in the platform memory but has never been verified because no artifacts have been saved.

### Gap

- No notification when artifacts are committed to the repository (no commit pipeline exists).
- No notification when research is stale or needs review.
- No scheduled re-search capability.

---

## 10. Assumptions & Gaps

### Assumptions

1. The Telegram Bot API is available and responsive. If Telegram is unreachable, the entire pipeline halts at Stage A.
2. The DeepSeek API (or fallback OpenRouter) is available. If both are unreachable, research cannot be executed.
3. Content storage directories (`~/.hermes/content/`) persist between container restarts. They are on the container's loop device — a container rebuild destroys all content.
4. The Research Analyst persona is present and loadable. If the SKILL.md is missing or corrupted, delegation fails silently.
5. The operator (John) has the authority to request research in any domain within RA's scope.

### Known Gaps

| Gap | Stage | Impact | Blocked By |
|-----|-------|--------|------------|
| No automated artifact saving | E | Research results exist only in chat history. No persistent record survives a session. | No post-completion hook in delegation workflow |
| No artifact versioning | E | If the same topic is researched twice, the second result overwrites the first in chat. No diff or history is available. | No artifact storage implementation |
| No commit automation | F | Final artifacts require manual git operations. Artifacts cannot enter the repository without operator direction. | No scripted commit pipeline |
| No stale-content detection | ALL | No mechanism to flag old research for re-review or archival. | No cron-based re-search scheduler |
| No cross-session memory accumulation | B | RA memory is a template file with no completed entries. Each session starts cold. | No append-on-completion automation |
| No routing metrics | B | No data exists on routing frequency, task duration, or persona workload distribution. | No instrumentation |
| No backup for research artifacts | ALL | Content directory is on the container loop device. Container rebuild = permanent loss of all research. | No backup capability (see docs/security.md §1.2) |

### Dependencies for Planned Stages

| Planned Capability | Required Dependency | Current Status |
|--------------------|-------------------|----------------|
| Artifact auto-commit | Git operations script with token auth | ✅ Available (manual only) |
| Artifact auto-commit | Review workflow (OM reviews before commit) | ⬜ Not designed |
| Scheduled re-search | Hermes cron jobs | 🟡 Cron infrastructure exists, no jobs configured |
| Cross-session memory accumulation | Append-on-completion hook in delegation | ⬜ Not designed |
| Content backup | Backup capability (LXD snapshot + secrets export) | ⬜ Not started |

---

## 11. Current State vs Planned State

### Current Capabilities (March 2026)

| Capability | Status |
|------------|--------|
| Receive research requests via Telegram | ✅ Operational |
| Route requests to Research Analyst persona | ✅ Operational |
| Execute research using DeepSeek + web tools | ✅ Operational |
| Produce structured output in chat | ✅ Operational |
| Deliver research results via Telegram | ✅ Operational |
| Load RA persona identity and rules via SKILL.md | ✅ Operational |
| Route fallback to OpenRouter on DeepSeek failure | ✅ Operational |

### Planned Capabilities (Next Implementation)

| Capability | Priority | Effort | Dependency |
|------------|----------|--------|------------|
| Save research artifacts to content storage | High | Low | Post-completion hook in delegation task |
| Record completed research in RA memory | High | Low | Append-on-completion logic |
| Automated backup for research artifacts | Critical | Low | Backup capability (container snapshot + secrets export) |

### Future Enhancements (Not Yet Scheduled)

| Enhancement | Notes |
|-------------|-------|
| Automated research artifact commit to repository | Requires review workflow and commit pipeline |
| Scheduled re-search for topics with high churn | Requires cron job + research topic registry |
| Cross-session research accumulation | Requires automated memory flushing |
| Research routing metrics dashboard | Requires instrumentation |
| Multi-provider parallel research | Requires orchestration changes |
