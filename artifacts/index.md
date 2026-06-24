# Knowledge Vault

> Filesystem-based knowledge reuse layer for persona agents.
> **Policy:** Register substantive artifacts automatically. Search before research.
> **Scope:** Research Analyst, Financial Analyst (Phase 1).

**Vault Version:** 1
**Created:** 2026-06-23
**Last Updated:** 2026-06-24
**Total Artifacts Registered:** 5

> [!NOTE]
> This index is the single source of truth for the Knowledge Vault. Every registered
> artifact appears here. The `register-artifact.sh` script manages entries — do not
> edit this file manually unless you are fixing a metadata error.

---

## Index

| Date | Title | Persona | Status | Tags | Freshness | Summary | Path |
|------|-------|---------|--------|------|-----------|---------|------|
| 2026-06-23 | Artifact Generation Architecture | Dev | `verified` | `architecture`, `artifact-generation`, `pipeline` | 90 days | Local-first artifact generation system with persona-namespaced storage, markdown templates, and script-driven workflow. | [artifacts/dev/2026-06-23_artifact-generation-architecture.md](dev/2026-06-23_artifact-generation-architecture.md) |
| 2026-06-23 | Telegram Bot Integration Architecture | Dev | `verified` | `architecture`, `telegram`, `gateway`, `messaging` | 90 days | Analysis of the Telegram gateway architecture covering adapter layer, message lifecycle, 10 delivery paths, and display configuration. | [artifacts/dev/2026-06-23_telegram-bot-integration-architecture.md](dev/2026-06-23_telegram-bot-integration-architecture.md) |
| 2026-06-23 | DeepSeek v4 Flash Provider Analysis | research-analyst | `draft` | `deepseek`, `provider`, `llm`, `api`, `analysis` | 30 days | Analysis of DeepSeek v4 Flash model covering performance benchmarks, pricing, and provider comparison. | [artifacts/research-analyst/2026-06-23_deepseek-v4-flash-provider-analysis.md](artifacts/research-analyst/2026-06-23_deepseek-v4-flash-provider-analysis.md) |
| 2026-06-23 | LXD vs Docker Comparison | research-analyst | `draft` | `lxd`, ` docker`, ` containerization`, ` comparison`, ` infrastructure` | 90 days | Comparison of LXD system containers vs Docker application containers for agent-hosting workloads. | [artifacts/research-analyst/2026-06-23_lxd-vs-docker-comparison.md](artifacts/research-analyst/2026-06-23_lxd-vs-docker-comparison.md) |
| 2026-06-24 | NVIDIA NIM Provider Validation | operations-manager | `verified` | `nvidia`, ` nim`, ` provider`, ` background`, ` maintenance`, ` delegation` | 90 days | Validation of NVIDIA NIM as a background maintenance provider for Hermes Agent. All three priority models responding. | [artifacts/operations-manager/2026-06-24_nvidia-nim-provider-validation.md](artifacts/operations-manager/2026-06-24_nvidia-nim-provider-validation.md) |
| 2026-06-24 | Architecture Documentation Audit — NVIDIA NIM Generated | operations-manager | `draft` | `nvidia`, ` nim`, ` audit`, ` architecture`, ` documentation`, ` background-maintenance` | 90 days | Architecture audit generated entirely by NVIDIA NIM (meta/llama-3.3-70b-instruct) as a background maintenance task. Zero DeepSeek tokens consumed. | [artifacts/operations-manager/2026-06-24_architecture-audit-nvidia-nim.md](artifacts/operations-manager/2026-06-24_architecture-audit-nvidia-nim.md) |
| 2026-06-23 | AAPL Q3 FY2026 Earnings Review | financial-analyst | `draft` | `aapl`, `apple`, `earnings`, `valuation`, `services`, `q3-2026` | 30 days | Apple Q3 FY2026 earnings review with revenue beat, Services milestones, and bull/bear case analysis. | [artifacts/financial-analyst/2026-06-23_aapl-q3-2026-earnings-review.md](artifacts/financial-analyst/2026-06-23_aapl-q3-2026-earnings-review.md) |
<!-- /Index-Table -->

---



## Statistics

| Metric | Value |
|--------|-------|
| Total artifacts | 7 |
| Last artifact | 2026-06-24 |
| Oldest artifact | 2026-06-23 |
| Fresh artifacts | 7 |
| Stale artifacts | 0 |
| Avg freshness threshold | 72 days |
| Most used tag | `architecture` (3) |
| Unique personas | 4 |
| Unique tags | 30 || research-analyst artifacts | 2 |
| financial-analyst artifacts | 1 |
| operations-manager artifacts | 2 |
| `draft` artifacts | 4 |
| `verified` artifacts | 3 |

---



## Quick Reference

### Registration (for persona agents)

```bash
./scripts/register-artifact.sh \
  --persona <research-analyst|financial-analyst> \
  --title "Artifact Title" \
  --status draft \
  --tags "tag1, tag2" \
  --freshness 90 \
  --summary "One-line summary of what this artifact contains." \
  --path "artifacts/<persona>/YYYY-MM-DD_title.md"
```

### Retrieval (for persona agents — before starting research)

1. **Search by keyword:** `grep -ril "keyword" artifacts/`
2. **Search by persona:** `find artifacts/<persona> -name "*.md"`
3. **Search by tag:** `grep -ril "tag1" artifacts/`
4. **Check freshness:** Compare `created` date against `freshness_days` threshold
5. **Read full content:** `cat artifacts/<persona>/YYYY-MM-DD_title.md`

### Full schema

| Field | Type | Description |
|-------|------|-------------|
| `title` | string | Human-readable artifact title |
| `persona` | string | Producing persona |
| `created` | date | ISO 8601 date (YYYY-MM-DD) |
| `status` | enum | `draft` or `verified` |
| `tags` | list | Comma-separated keywords |
| `summary` | string | One-line description of content |
| `path` | string | Relative path from repo root |
| `freshness_days` | int | Days before artifact is considered stale |
