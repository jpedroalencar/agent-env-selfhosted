# Knowledge Vault — Workflow

> **Audience:** All persona agents (Research Analyst, Financial Analyst, Dev, Operations Manager).
> **Purpose:** Prevent duplicate research through retrieval-before-research.
> **Phase 2:** Automated workflows, cross-persona vault coverage, auto-registration, freshness checks, reuse decisions, cron-based stale detection.
> **Last updated:** 2026-06-24

---

## Table of Contents

1. [Overview](#1-overview)
2. [Substantive Check → Vault Search → Freshness → Reuse or Research](#2-substantive-check--vault-search--freshness--reuse-or-research)
3. [Metadata Schema](#3-metadata-schema)
4. [Registration Policy](#4-registration-policy)
5. [Quality Policy](#5-quality-policy)
6. [Retrieval Policy](#6-retrieval-policy)
7. [Freshness Rules](#7-freshness-rules)
8. [Retrieval-Before-Research Workflow](#8-retrieval-before-research-workflow)
9. [Artifact Reuse Workflow](#9-artifact-reuse-workflow)
10. [Stale Artifact Refresh Workflow](#10-stale-artifact-refresh-workflow)
11. [Registration Procedure](#11-registration-procedure)
12. [Phase 2: Automated Workflows](#12-phase-2-automated-workflows)
13. [Phase 2: Cron-Based Vault Maintenance](#13-phase-2-cron-based-vault-maintenance)
14. [Phase 2: Script Reference](#14-phase-2-script-reference)
15. [Operational Limits](#15-operational-limits)
16. [Known Gaps (Phase 2)](#16-known-gaps-phase-2)

---

## 1. Overview

The Knowledge Vault is a lightweight filesystem-based knowledge reuse layer. It uses plain Markdown and shell scripts — no databases, embeddings, or external services.

**Core principle:** Before performing research, analysis, planning, or evaluation, search the vault first. If a relevant and fresh artifact already exists, reuse it instead of performing new work.

**Phase 1 scope:** Research Analyst and Financial Analyst only.
**Phase 2 scope:** All personas including Dev and Operations Manager. Automated retrieval workflows, freshness evaluation, and cron-based stale detection.

### Phase 2 Workflow Architecture

```
User Request / Task
   │
   ├── 1. Substantive Check
   │       └── Is this a task that warrants vault search?
   │             ├── Yes → Continue
   │             └── No → Execute normally, skip vault
   │
   ├── 2. Vault Search (lookup-artifact.sh)
   │       └── Search by keyword, tag, persona, or full-text
   │
   ├── 3. Freshness Evaluation (freshness-check.sh)
   │       ├── Fresh → Continue to reuse evaluation
   │       └── Stale → Offer refresh or skip to research
   │
   ├── 4. Reuse Decision (reuse-artifact.sh)
   │       ├── Reuse → Cite artifact, deliver response
   │       ├── Reuse + Supplement → Cite + targeted research on gaps
   │       ├── Refresh → Perform refresh, update artifact, re-register
   │       └── Research → Perform new research
   │
   ├── 5. Artifact Generation (generate-artifact.sh)
   │       ├── Generate artifact file
   │       └── Auto-register in vault (AUTO_REGISTER=true)
   │
   └── 6. Registration (register-artifact.sh)
             ├── Add to index with metadata
             └── Auto-compute statistics (update-index-stats.sh)
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

## 11. Registration Procedure

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

### Phase 2: Automatic Registration (generate-artifact.sh)

In Phase 2, artifact generation now automatically triggers registration. When using `generate-artifact.sh`, registration happens implicitly:

```bash
# Generate AND auto-register in one step:
AUTO_REGISTER=true \
REGISTER_STATUS=draft \
REGISTER_TAGS="deepseek, provider, llm" \
REGISTER_FRESHNESS=30 \
./scripts/generate-artifact.sh research-analyst "DeepSeek Analysis" /tmp/content.md
```

After generation and registration, vault statistics are automatically recomputed.

### Phase 2: Automatic Statistics Update

After every successful registration, `update-index-stats.sh` runs automatically to keep the Statistics section in `artifacts/index.md` current. This replaces the Phase 1 manual update requirement.

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

## 12. Phase 2: Automated Workflows

### 12.1 Structured Artifact Lookup

The `lookup-artifact.sh` script provides structured search with relevance evaluation and freshness detection.

```bash
# Search by keyword
./scripts/lookup-artifact.sh --query "deepseek"

# Search within a persona
./scripts/lookup-artifact.sh --query "lxd" --persona research-analyst

# Search by tag
./scripts/lookup-artifact.sh --query "architecture" --tag architecture

# Fresh artifacts only
./scripts/lookup-artifact.sh --query "earnings" --freshness-only

# List all artifacts with freshness status
./scripts/lookup-artifact.sh --list-all

# List only stale artifacts
./scripts/lookup-artifact.sh --list-stale

# Machine-readable JSON output
./scripts/lookup-artifact.sh --query "aapl" --json
```

**Output format:** Each result shows:
- Title, persona, date, status
- Freshness evaluation: `✅ FRESH (Xd old, threshold Yd)` or `⚠️ STALE (Xd old, threshold Yd)`
- Tags and summary
- File path

### 12.2 Freshness Evaluation

The `freshness-check.sh` script evaluates vault freshness across all or targeted artifacts.

```bash
# Check all artifacts
./scripts/freshness-check.sh

# Check one persona
./scripts/freshness-check.sh --persona financial-analyst

# Custom warning threshold (warn 14 days before stale)
./scripts/freshness-check.sh --warn-days 14

# Brief summary only
./scripts/freshness-check.sh --summary-only

# JSON for programmatic consumption
./scripts/freshness-check.sh --json

# Exit code mode (exit 1 if any stale) — for cron alerting
./scripts/freshness-check.sh --exit-code
```

**Categorization:**
| Category | Condition | Action |
|----------|-----------|--------|
| ✅ Fresh | `age <= freshness_days` | No action needed |
| ⚡ Warning | `(freshness_days - age) <= warn_days` | Plan for refresh |
| ⚠️ Stale | `age > freshness_days` | Refresh recommended |

### 12.3 Reuse Decision Framework

The `reuse-artifact.sh` script takes a lookup result and a user request, evaluates coverage and freshness, and produces a structured decision.

```bash
# Basic reuse evaluation
./scripts/reuse-artifact.sh \
  --artifact-path "artifacts/research-analyst/2026-06-23_deepseek-v4-flash-provider-analysis.md" \
  --request "Compare DeepSeek v4 Flash pricing against OpenAI"

# Force reuse (skip coverage evaluation)
./scripts/reuse-artifact.sh \
  --artifact-path "artifacts/financial-analyst/2026-06-23_aapl-q3-2026-earnings-review.md" \
  --request "What's Apple's current P/E ratio?" \
  --force-reuse

# JSON output
./scripts/reuse-artifact.sh --artifact-path "<path>" --request "<query>" --json
```

**Decision outcomes:**
| Decision | Meaning | Action Required |
|----------|---------|-----------------|
| `reuse` | Good coverage + fresh | Cite artifact, deliver response |
| `reuse_with_caution` | Fresh but coverage unclear | Cite artifact, add caveat |
| `reuse_with_supplement` | Partial coverage + fresh | Cite artifact, research gaps |
| `refresh` | Good coverage but stale | Refresh artifact, update date |
| `research` | Poor coverage or stale | Full new research |

### 12.4 Citation Template

When an artifact is reused, agents MUST use this citation format:

```
[Knowledge Vault — Artifact Reused]
  Title: <Title>
  Path: <Relative path from repo root>
  Persona: <Persona>
  Freshness: <Age>/<Threshold> days (fresh|stale)
  Summary: <One-line summary>
```

---

## 13. Phase 2: Cron-Based Vault Maintenance

### 13.1 Stale Artifact Check

The `stale-check-cron.sh` script is designed to run as a cron job for proactive stale detection.

```bash
# Default: full human-readable report
./scripts/stale-check-cron.sh

# Summary only (quiet cron mode)
./scripts/stale-check-cron.sh --summary-only

# Markdown notification format (for Telegram delivery)
./scripts/stale-check-cron.sh --notify

# Cron-optimized output (multi-line, no decoration)
./scripts/stale-check-cron.sh --cron-report

# Custom warning threshold
./scripts/stale-check-cron.sh --warn-days 14
```

### 13.2 Cron Job Setup

```bash
# Weekly stale check (every Monday at 9 AM)
hermes cron create \
  --schedule "0 9 * * 1" \
  --prompt "Run stale check on Knowledge Vault" \
  --name "vault-stale-check"
```

Or with the script directly as a cron script job:

```bash
# Weekly stale check via script
hermes cron create \
  --schedule "0 9 * * 1" \
  --script "scripts/stale-check-cron.sh" \
  --no-agent true \
  --name "vault-stale-check"
```

### 13.3 Automated Artifact Registration Chain

The following automatic chain runs when an artifact is generated:

```
generate-artifact.sh
  └── Creates artifact file
  └── Calls register-artifact.sh (if AUTO_REGISTER=true)
        └── Injects YAML frontmatter
        └── Appends index entry
        └── Logs registration
        └── Calls update-index-stats.sh
              └── Recomputes vault statistics
              └── Updates Statistics section in index.md
```

---

## 14. Phase 2: Script Reference

| Script | Purpose | Phase | Output |
|--------|---------|-------|--------|
| `scripts/generate-artifact.sh` | Create artifact file | Phase 1 + 2 | File path |
| `scripts/register-artifact.sh` | Register in vault index | Phase 1 + 2 | Registration log |
| `scripts/lookup-artifact.sh` | Structured vault search | Phase 2 | Ranked results with freshness |
| `scripts/freshness-check.sh` | Full vault freshness eval | Phase 2 | Stale/fresh/warning counts |
| `scripts/reuse-artifact.sh` | Reuse decision framework | Phase 2 | Decision + citation stub |
| `scripts/update-index-stats.sh` | Auto-compute index stats | Phase 2 | Updated Statistics section |
| `scripts/stale-check-cron.sh` | Cron-based stale detection | Phase 2 | Alert report |

### Persona Coverage

| Persona | Phase 1 | Phase 2 |
|---------|---------|---------|
| Research Analyst | ✅ Search + Register | ✅ Lookup + Freshness + Reuse |
| Financial Analyst | ✅ Search + Register | ✅ Lookup + Freshness + Reuse |
| Dev | ❌ Excluded | ✅ Full vault workflow |
| Operations Manager | ❌ Excluded | ✅ Full vault workflow |

---

## 15. Operational Limits

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

## 16. Known Gaps (Phase 2)

| Gap | Impact | Planned Resolution |
|-----|--------|-------------------|
| No cross-session artifact awareness | Each session starts cold — agent must read index file to learn about past artifacts | Phase 3: auto-load vault index into context |
| No concurrency control | Simultaneous registrations could race | Phase 3: lockfile or atomic write |
| Manual search (grep) | No structured query language | grep with tags is sufficient for Phase 2 scale |
| No automated refresh execution | Stale detection works but refresh is manual | Phase 3: AI-driven auto-refresh on cron tick |
| No notification when artifact is reused | No feedback loop to measure vault effectiveness | Phase 3: reuse audit log |
| Statistics not recomputed on delete | If artifact is removed, stats become stale | Phase 3: delete workflow with stats update |
