# Knowledge Vault — Workflow

> **Audience:** Research Analyst, Financial Analyst personas (Phase 1).
> **Purpose:** Prevent duplicate research through retrieval-before-research.
> **Last updated:** 2026-06-23

---

## Table of Contents

1. [Overview](#1-overview)
2. [Metadata Schema](#2-metadata-schema)
3. [Registration Policy](#3-registration-policy)
4. [Quality Policy](#4-quality-policy)
5. [Retrieval Policy](#5-retrieval-policy)
6. [Freshness Rules](#6-freshness-rules)
7. [Retrieval-Before-Research Workflow](#7-retrieval-before-research-workflow)
8. [Artifact Reuse Workflow](#8-artifact-reuse-workflow)
9. [Stale Artifact Refresh Workflow](#9-stale-artifact-refresh-workflow)
10. [Registration Procedure](#10-registration-procedure)
11. [Operational Limits](#11-operational-limits)
12. [Known Gaps (Phase 1)](#12-known-gaps-phase-1)

---

## 1. Overview

The Knowledge Vault is a lightweight filesystem-based knowledge reuse layer. It uses plain Markdown and shell scripts — no databases, embeddings, or external services.

**Core principle:** Before performing research, analysis, planning, or evaluation, search the vault first. If a relevant and fresh artifact already exists, reuse it instead of performing new work.

**Scope (Phase 1):** Research Analyst and Financial Analyst only. Dev and Operations Manager are excluded from automated retrieval requirements in Phase 1.

**Architecture:**

```
Persona Agent
   │
   ├── 1. Search Knowledge Vault (artifacts/index.md + grep/find)
   │
   ├── 2. Match found?
   │      ├── Yes → Evaluate freshness
   │      │           ├── Fresh → Reuse (cite artifact)
   │      │           └── Stale → Inform user, offer refresh
   │      └── No → Perform new research
   │                 └── Register result as artifact
   │
   └── 3. Deliver response
```

---

## 2. Metadata Schema

Every registered artifact carries the following metadata in both YAML frontmatter (in the artifact file) and index entry (in `artifacts/index.md`):

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `title` | string | Yes | Human-readable artifact title |
| `persona` | string | Yes | Producing persona (e.g. `research-analyst`) |
| `created` | date | Yes | ISO 8601 date (`YYYY-MM-DD`) |
| `status` | enum | Yes | `draft` or `verified` |
| `tags` | list | Yes | Comma-separated keywords for search |
| `freshness_days` | int | Yes | Days before artifact is considered stale |
| `summary` | string | Yes | One-line description of artifact content |
| `path` | string | Yes | Relative path from repo root to artifact file |

### YAML Frontmatter Example

```yaml
---
title: DeepSeek Provider Analysis
persona: research-analyst
created: 2026-06-23
status: draft
tags: [provider, deepseek, api, llm]
freshness_days: 30
summary: Analysis of DeepSeek as primary LLM provider covering performance, cost, and reliability.
path: artifacts/research-analyst/2026-06-23_deepseek-provider-analysis.md
---
```

---

## 3. Registration Policy

### When to Register

Register automatically **immediately after creating a substantive artifact**. Registration must not require operator action.

### Automatic Registration Triggers

The persona agent MUST call `register-artifact.sh` after completing any substantive work that produced a new artifact file. This applies to both human-initiated tasks and autonomous cron-driven tasks.

### Duplicate Prevention

The registration script checks for existing entries matching the same `title` + `persona` combination. Duplicate registration attempts exit with code 2 and log the event.

### Failure Handling

Registration failures are:

1. Logged to `~/.hermes/vault-logs/register-*.log` with full metadata and error reason
2. Reported to the user in the delivery response
3. NOT silently swallowed

### No-Op Registration

The registration script must be idempotent for the same title + persona — re-running with identical metadata is a no-op (fails early, logs, does not corrupt the index).

---

## 4. Quality Policy

### Register ✅ (Substantive Artifacts Only)

| Type | Examples |
|------|----------|
| Research reports | Deep-dive analysis, competitive intelligence, literature reviews |
| Market analysis | Sector overviews, trend analysis, regulatory landscapes |
| Valuation reports | Company analysis with P/E, PEG, bull/bear cases |
| Earnings reviews | Quarterly results, key metrics vs. expectations |
| Portfolio analysis | Allocation reviews, rebalancing suggestions, risk assessments |
| Architecture documents | Design decisions, trade-off analysis, system diagrams |
| Investment theses | Buy/sell/hold rationale with evidence |
| Implementation plans | Scope, steps, dependencies, timeline |

### Do NOT Register ❌

| Type | Examples |
|------|----------|
| Greetings | "Hello", "How can I help?" |
| Status updates | "Working on it", "Completed task" |
| Short responses | Under ~200 words, no analytical content |
| Troubleshooting notes | "Changed config X to fix Y" (one-off fixes) |
| Operational acknowledgements | "Acknowledged", "Noted", "Roger" |
| Tool outputs | Raw terminal output, API responses, log dumps |
| Transient investigations | Quick lookups that won't be useful again in 30 days |
| Configuration snippets | Single commands or env variable changes |

**Optimize for signal quality, not artifact count.** A vault with 50 high-signal artifacts is more valuable than one with 500 noise entries.

---

## 5. Retrieval Policy

**Before performing** any of the following activities, the persona MUST search the Knowledge Vault first:

- Research
- Analysis
- Planning
- Architecture design
- Evaluations
- Investment theses / valuations

### Retrieval Sequence

```
Step 1: Search Vault         ← grep, find, or browse index
   │
   ├── No match found
   │     └── Proceed with new research
   │
   └── Match found
         │
         ├── Evaluate relevance
         │     ├── Relevant → Step 2
         │     └── Not relevant → Proceed with new research
         │
         ├── Step 2: Evaluate freshness (compare created + freshness_days vs today)
         │     ├── Fresh → Reuse artifact
         │     └── Stale → Inform user, present summary, offer refresh
         │
         └── Step 3: Deliver
               ├── Fresh reuse: Cite artifact, summarize findings
               └── Stale: "Existing artifact found but stale (X days old). Refreshing..."
```

### Search Commands

```bash
# Search by keyword (content search)
grep -ril "deepseek" artifacts/

# Search by tag in index
grep "deepseek" artifacts/index.md

# Search by persona
ls artifacts/research-analyst/

# Browse all artifacts
cat artifacts/index.md
```

---

## 6. Freshness Rules

### Fast-Moving Topics — `freshness_days: 30`

| Topic Area | Examples |
|------------|----------|
| Provider/API status | DeepSeek, Anthropic, OpenAI availability, pricing changes |
| Model comparisons | Benchmarks, performance rankings, new releases |
| Competitive news | New entrants, acquisitions, shutdowns |
| Security advisories | Patches, CVE disclosures |
| Market conditions | Rapidly changing market data |

### Stable Topics — `freshness_days: 90`

| Topic Area | Examples |
|------------|----------|
| Architecture decisions | Design trade-offs, system diagrams |
| Platform configuration | Setup procedures, deployment topology |
| Technology evaluations | Tool comparisons on stable criteria |
| Investment frameworks | Valuation methodology, analytical models |
| Workflow definitions | Runbooks, SOPs, pipeline descriptions |

### Stale Detection Formula

```
stale = (today - created_date) > freshness_days
```

### Auto-Refresh Triggers

Refresh an artifact automatically when:

- Current information on the same topic is requested
- The topic is inherently time-sensitive (status, pricing, availability)
- The user explicitly requests an update
- The artifact is stale AND the request is for information the artifact could provide

### Refresh Behavior

When refreshing a stale artifact:

1. Inform the user before performing the refresh
2. Present a summary of the existing artifact (title, date, key findings)
3. Offer to refresh or ask if fresh research is needed
4. After producing new content, update the artifact file and re-register (update metadata, change date)

---

## 7. Retrieval-Before-Research Workflow

This is the primary workflow that persona agents MUST follow before any research activity.

### Step-by-Step

```
[R] ── 1. New research request received
[R] ── 2. Search Knowledge Vault for relevant artifacts
          │
          ├── 2a. Read artifacts/index.md
          ├── 2b. grep -ril "<topic>" artifacts/
          └── 2c. Browse persona directory: ls artifacts/<persona>/
               
[R] ── 3. Evaluate results
          │
          ├── No relevant artifact found
          │     └── Proceed directly to research
          │
          └── Relevant artifact found
                │
                ├── 3a. Read artifact content
                ├── 3b. Evaluate freshness
                │
                ├── Fresh:
                │     └── Deliver response citing artifact
                │
                └── Stale:
                      └── Follow stale-artifact workflow (§9)
               
[R] ── 4. After new research
          ├── 4a. Generate artifact file
          └── 4b. Register with register-artifact.sh

[R] = Responsibility of the persona agent
```

### Persona Responsibility

The persona agent (not the orchestrator, not the user) is responsible for executing this workflow. The vault lookup is built into the persona's task execution — it is not an optional step.

---

## 8. Artifact Reuse Workflow

When a relevant and fresh artifact is found:

1. **Read** the artifact file to understand its content
2. **Assess** whether it fully answers the current request
3. **Complement** with additional research only if gaps exist
4. **Deliver** response that:
   - Summarizes the existing findings
   - Cites the artifact by path
   - Adds any new context or updates
   - Does NOT duplicate the full artifact content in the response

### Reuse Report Example

```
[Knowledge Vault — Artifact Reused]
Title: AAPL Q3 FY2026 Earnings Review
Path: artifacts/financial-analyst/2026-06-23_aapl-q3-2026-earnings.md
Freshness: 23/30 days (fresh)

Summary: Revenue beat estimates by 3.2% driven by Services growth.
Services segment reached $25B for the first time. iPhone revenue
flat YoY.

Additional context since publication: Wedbush upgraded target
to $280 on AI tailwinds. See [source].
```

---

## 9. Stale Artifact Refresh Workflow

When a relevant but stale artifact is found:

```
[R] ── 1. Identify stale artifact
[R] ── 2. Inform user: "Found existing coverage from [date]. It's [X days] stale."
[R] ── 3. Offer: "I can refresh this or perform fresh research."
          │
          ├── User confirms refresh
          │     └── Perform new research on the topic
          │           ├── Update the artifact file with new content
          │           └── Re-register: update YAML frontmatter with new date
          │
          └── User requests fresh research
                └── Perform new research as a new artifact
```

---

## 10. Registration Procedure

### Step-by-Step for Persona Agents

After creating a substantive artifact file:

```bash
cd /path/to/repo
./scripts/register-artifact.sh \
  --persona "research-analyst" \
  --title "DeepSeek v4 Flash Analysis" \
  --status "draft" \
  --tags "deepseek, provider, llm, api" \
  --freshness 30 \
  --summary "Analysis of DeepSeek v4 Flash model covering performance benchmarks, pricing, and provider comparison." \
  --path "artifacts/research-analyst/2026-06-23_deepseek-v4-flash-analysis.md"
```

### Verification

After running, verify:

1. **Artifact file** has YAML frontmatter: `head -10 artifacts/research-analyst/your-file.md`
2. **Index entry** exists: `grep "Your Title" artifacts/index.md`
3. **Log file** exists: `ls .hermes/vault-logs/`

### Failure Diagnosis

| Exit Code | Meaning | Action |
|-----------|---------|--------|
| 0 | Success | No action needed |
| 1 | Missing arguments | Check all -- flags are provided |
| 2 | Duplicate | Check if artifact already registered; if so, no action needed |
| 3 | File not found | Check that --path is correct and file exists |
| 4 | Index write failure | Check file permissions on artifacts/index.md |
| 5 | Frontmatter injection failure | Check artifact file structure |
| 6 | Validation failure | Check persona/status/freshness values |

---

## 11. Operational Limits

### Architecture Boundaries (Phase 1)

The following are **explicitly out of scope** for the Knowledge Vault:

| Technology | Reason |
|------------|--------|
| Vector databases | Overengineered for Phase 1 scale |
| Embeddings | Not needed for keyword-based retrieval |
| RAG pipelines | No semantic search or chunking required |
| Dashboards | Not needed — grepping the index is sufficient |
| Semantic search services | Filesystem tools (grep, find) are adequate |
| External databases | Single-repo markdown is the durable source |

### Scalability Limits

The Phase 1 design is suitable for:
- Up to ~200 artifacts total
- Keyword-based retrieval on a single-repo filesystem
- Single-agent registration (no concurrent write contention)

---

## 12. Known Gaps (Phase 1)

| Gap | Impact | Planned Resolution |
|-----|--------|-------------------|
| No cross-session artifact awareness | Each session starts cold — agent must read index file to learn about past artifacts | Phase 2: auto-load vault index into context |
| No automated stale checking | Persona agents must compute freshness manually | Phase 2: cron-based stale check |
| No Dev/OM Phase 1 integration | Dev and OM won't register or search vault | Phase 2: extend to all personas |
| No concurrency control | Simultaneous registrations could race | Phase 2: lockfile or atomic write |
| Manual search (grep) | No structured query language | grep with tags is sufficient for Phase 1 |
