# Architecture

System architecture and design decisions for the self-hosted AI agent platform.

> **Provenance:** This document was consolidated from the repository's original `docs/architecture.md` and the root-level `ARCHITECTURE.md` on 2026-06-24. Unique content from the root document has been merged here; the root file is now deprecated.

---

## Current Architecture

### Physical Topology

```text
Oracle Cloud VPS (Ubuntu 24.04 LTS, aarch64)
├── UFW Firewall (host-level, inbound-restricted)
├── Fail2Ban (host-level, SSH brute-force protection)
├── LXD Hypervisor
│   └── Unprivileged LXC Container (Debian 12 Bookworm)
│       ├── Hermes Agent v0.17.0
│       │   ├── Primary Provider: DeepSeek (deepseek-v4-flash)
│       │   ├── Fallback Provider: OpenRouter (gemini-2.0-flash)
│       │   ├── Chat Platform: Telegram
│       │   └── Local CLI: Direct terminal access
│       ├── GitHub Integration (bot account: johnalencar-agent)
│       ├── Knowledge Vault (artifacts/, 8 registered)
│       ├── Local Secret Store (/root/.config/hermes/secrets.env)
│       └── Python 3.11.2 Runtime
├── Backup & Recovery (host-side)
│   ├── backup-container.sh (snapshot + retention + evidence)
│   ├── restore-container.sh (interactive restore with safety checks)
│   ├── /var/log/hermes-backup.log
│   └── Host validation evidence → injected into container
└── 40 GB Boot Volume (loop device)
```

### Host Layer

- **Provider:** Oracle Cloud Infrastructure (OCI), free-tier Ampere A1 instance
- **CPU:** 2× Neoverse-N1 (ARM aarch64) @ ~3.0 GHz
- **RAM:** 8 GB
- **Kernel:** 6.17.0-1011-oracle (OCI-optimized kernel for Ubuntu 24.04; the `-oracle` suffix is the kernel flavor, not the OS distribution)
- **Hypervisor:** LXD — manages one unprivileged LXC container

### Container Layer

- **Guest OS:** Debian 12 Bookworm (chosen for stability and minimal overhead)
- **Filesystem:** 40 GB loop device, ~33 GB available
- **Isolation:** Unprivileged container — root inside container is mapped to a non-privileged UID on the host
- **Network:** Outbound-only by default; container initiates all connections (no inbound ports exposed)

### Agent Layer

- **Hermes Agent v0.17.0** installed at `/usr/local/lib/hermes-agent`
- **Model:** `deepseek-v4-flash` via `https://api.deepseek.com`
- **Fallback chain:** OpenRouter → `google/gemini-2.0-flash`
- **Platform integration:** Telegram (primary), CLI (direct)
- **Agent configuration:** `/root/.hermes/config.yaml`
- **Memory store:** Filesystem-based (`~/.hermes/memories/MEMORY.md`, `USER.md`)
- **Skills:** See `skills_list` for current count (categories include development, research, data science, creative, devops, GitHub, social media, smart home, productivity, email, media, research, documentation, note-taking, MLOps, autonomous agents, and more)
- **Tools:** web search, browser automation, terminal, file ops, code execution, vision, delegation
- **Knowledge Vault:** Filesystem-based knowledge reuse layer at `artifacts/` — retrieval-before-research for Research Analyst and Financial Analyst personas
- **Backup:** Automated LXD snapshot backup with retention (7 days) and host validation evidence injected into `artifacts/operations-manager/host-validation/`

### Persona Architecture

The four specialist agent personas operate under a single Orchestrator profile:

```
Orchestrator (Telegram coordinator)
├── Financial Analyst   — Stocks, ETFs, valuation, earnings, macro, portfolio
├── Research Analyst    — Deep research, market intel, competitive analysis
├── Dev                 — Code, infrastructure, VPS, LXD, Hermes config, automation
└── Operations Manager  — Planning, docs, roadmaps, project management
```

Each persona has:
- A **SKILL.md** definition under `~/.hermes/skills/personas/<name>/`
- A **workspace** directory under `~/.hermes/personas/<name>/workspace/`
- A **memory file** at `~/.hermes/personas/<name>/memory.md`
- Strict **role boundaries** enforced by the Orchestrator

### Storage Layout

```text
~/.hermes/
├── config.yaml              # Master configuration
├── content/                 # Agent-generated content (one subdir per persona)
├── cron/                    # Scheduled job definitions and output
├── memories/                # Agent-level persistent memory
├── personas/                # Persona workspaces and memory
├── skills/                  # Skill definitions (73 installed)
└── plugins/                 # Plugin directory (not yet populated)
```

### Security Boundaries

| Boundary | Mechanism | Status |
|----------|-----------|--------|
| Host ↔ Container | LXD unprivileged container | ✅ Implemented |
| Container ↔ Internet | Outbound-only, no inbound ports | ✅ Implemented |
| API Credentials | Local file (`secrets.env`), not in repo | ✅ Implemented |
| Agent ↔ LLM API | HTTPS, API key auth | ✅ Implemented |
| Chat Authentication | Telegram token + chat allowlist | ✅ Implemented |
| Repo Security | .gitignore exclusions, secret scanning | ✅ Implemented |
| TIRITH Policy Engine | Available, disabled | 🔧 Configured off |
| Caddy / WAF | Not yet deployed | ⬜ Planned |
| OAuth / SSO | Not yet deployed | ⬜ Planned |

---

## System Philosophy

The Orchestrator Agent Platform was built to solve a specific problem: **a single general-purpose agent is bad at everything**.

A single Hermes Agent instance, given a complex multi-domain task (e.g., "research Company X, analyze its financial health, build a dashboard, and deploy it"), will:

- Hallucinate financial data it can't verify
- Write code it can't test in the same session
- Forget the original request halfway through
- Mix up context between domains

**The solution:** Split the work across specialized persona agents, each with:
- A narrow domain of expertise
- Its own memory (only relevant context)
- Its own toolset (no unnecessary attack surface)
- Its own configuration

The Orchestrator acts as a **routing supervisor** — it decomposes user requests, delegates to the right persona, validates results, and composes the final answer.

### Why Not Plugins?

Hermes Agent supports plugins. Separate profiles were chosen instead because:

| Concern | Plugins | Profiles |
|---------|---------|----------|
| Context isolation | Shared memory space | Fully isolated memories |
| Tool conflicts | Merged tool namespace | Per-profile tool sets |
| Independent updates | Must update plugin API | Can change any profile independently |
| Failure isolation | One plugin crash can affect runtime | Profile crash is contained |
| Testing | Must test integrated | Can test each persona in isolation |

> **Lesson learned:** Profile isolation was the right call. Early experiments with plugins showed memory bleeding within 2-3 turns — the Dev persona would start answering financial questions using its own (incorrect) data.

---

## Agent Topology

```
                        ┌─────────────────────────────────┐
                        │         User Request             │
                        └──────────────┬──────────────────┘
                                       │
                                       ▼
              ┌─────────────────────────────────────┐
              │        Orchestrator Agent           │
              │  (Root — Telegram coordinator)      │
              │  Role: Decompose, Delegate, Compose │
              │  Memory: Delegation history, user    │
              │          preferences, routing state  │
              │  Tools: Profile switching, file I/O  │
              └──────┬────────────┬──────────┬──────┘
                     │            │          │
           ┌─────────┘    ┌───────┘   ┌──────┘
           ▼              ▼            ▼
   ┌──────────────┐ ┌───────────┐ ┌──────────┐
   │  Financial   │ │ Research  │ │   Dev    │
   │  Analyst     │ │ Analyst   │ │          │
   │              │ │           │ │          │
   │ Profile:     │ │ Profile:  │ │ Profile: │
   │ financial-   │ │ research- │ │ dev      │
   │ analyst      │ │ analyst   │ │          │
   │              │ │           │ │          │
   │ Tools:       │ │ Tools:    │ │ Tools:   │
   │ Python, yf   │ │ Web,      │ │ Git,     │
   │ File I/O     │ │ Search    │ │ Python,  │
   │              │ │ File I/O  │ │ Build    │
   └──────────────┘ └───────────┘ └──────────┘
          │              │              │
          └──────────────┼──────────────┘
                         ▼
              ┌──────────────────────┐
              │   Operations Manager │
              │   (Profile: ops-     │
              │    manager)          │
              │                      │
              │   Role: Lifecycle,   │
              │   Monitoring,        │
              │   Recovery           │
              │                      │
              │   Tools: Health      │
              │   checks, Log        │
              │   analysis,          │
              │   File diagnostics   │
              └──────────────────────┘
```

### Persona Roles

| Persona | Domain | Key Constraint | Tools |
|---------|--------|---------------|-------|
| **Orchestrator** | Entry point for all requests. Never performs domain work. | Must never perform domain work — delegate everything. | `profile_switch`, `file_read`, `file_write` |
| **Financial Analyst** | Financial data analysis, stock valuation, ratio calculation, financial statement interpretation | Must cite the source of every data point. Never fabricate financial figures. | Python (pandas, yfinance), file output |
| **Research Analyst** | Web research, fact-checking, competitive analysis, market research | Must provide source URLs for every claim. Never extrapolate beyond sourced data. | Web fetch, search, scraping |
| **Dev** | Software development, code generation, repository management, build & test | Must test code before declaring it complete. Must document dependencies. | Git, Python, build systems, file I/O, package managers |
| **Operations Manager** | Health monitoring, recovery procedures, configuration management, alerting | Should never modify persona memory without Orchestrator approval. Read-only for health checks by default. | Profile status checks, log inspection, filesystem diagnostics, process management |

---

## Delegation Flow

The complete lifecycle of a single delegated subtask:

```
1. DECOMPOSE
   ┌─────────────────────────────────────────────────────┐
   │ Orchestrator parses user request into subtasks.     │
   │ E.g.: "Analyze Tesla" →                             │
   │   Subtask A: Research recent Tesla news (Research)  │
   │   Subtask B: Fetch Tesla financials (Financial)     │
   │   Subtask C: Create dashboard (Dev)                 │
   └─────────────────────────────────────────────────────┘
                              │
                              ▼
2. ROUTE
   ┌─────────────────────────────────────────────────────┐
   │ Orchestrator checks routing table:                  │
   │   • "research" → research-analyst                   │
   │   • "financial" → financial-analyst                 │
   │   • "create dashboard" → dev                        │
   │ Prepares subtask brief with:                        │
   │   • Clear objective                                 │
   │   • Input data/context                              │
   │   • Output format requirements                      │
   │   • Validation criteria                             │
   └─────────────────────────────────────────────────────┘
                              │
                              ▼
3. DELEGATE
   ┌─────────────────────────────────────────────────────┐
   │ Orchestrator launches persona session with brief.   │
   │ Orchestrator sets a timeout (default: 120s per      │
   │ subtask). If persona doesn't complete in time,      │
   │ the task is marked FAILED_TIMEOUT.                  │
   └─────────────────────────────────────────────────────┘
                              │
                              ▼
4. EXECUTE
   ┌─────────────────────────────────────────────────────┐
   │ Persona agent receives subtask brief.               │
   │ Uses its own memory, tools, and skills to complete  │
   │ the task. Reports progress or asks clarifying       │
   │ questions back to Orchestrator if needed.           │
   └─────────────────────────────────────────────────────┘
                              │
                              ▼
5. VALIDATE
   ┌─────────────────────────────────────────────────────┐
   │ Orchestrator receives persona output.               │
   │ Checks against validation criteria from step 2.     │
   │                                                     │
   │ Possible outcomes:                                  │
   │   ✓ PASS → compose into final response              │
   │   ✗ FAIL_FORMAT → re-route with format feedback     │
   │   ✗ FAIL_CONTENT → re-route with content feedback   │
   │   ✗ FAIL_TIMEOUT → retry once, then abort task      │
   └─────────────────────────────────────────────────────┘
                              │
                              ▼
6. COMPOSE
   ┌─────────────────────────────────────────────────────┐
   │ Orchestrator gathers all validated outputs.         │
   │ Synthesizes into final response for the user.       │
   │ References which persona produced which part.       │
   │ Stores delegation record in own memory.             │
   └─────────────────────────────────────────────────────┘
```

### Synchronous vs. Asynchronous

**Current implementation (v0.1):** Synchronous. The Orchestrator delegates one subtask at a time, waits for completion, validates, then proceeds to the next. This is simpler to debug and audit.

**Planned (v0.3):** Asynchronous for independent subtasks. The research and financial analysis subtasks in the example above are independent — they could run in parallel. The Dashboard subtask depends on both, so it must wait.

---

## Profile Isolation Model

Each persona runs as a **separate Hermes Agent profile**. This is the bedrock isolation mechanism.

### Filesystem Layout

```
~/.hermes/
├── profiles/
│   ├── orchestrator/
│   │   ├── config.yaml            # Orchestrator settings
│   │   ├── skills/                # Skills loaded for Orchestrator
│   │   ├── plugins/               # Orchestrator-specific plugins
│   │   ├── cron/                  # Scheduled tasks
│   │   └── memories/              # Delegation history, preferences
│   ├── financial-analyst/
│   │   ├── config.yaml            # FA-specific config
│   │   ├── skills/                # Financial analysis skills
│   │   ├── memories/              # Market data context, valuation notes
│   │   └── ...
│   ├── research-analyst/
│   │   ├── config.yaml
│   │   ├── skills/
│   │   ├── memories/
│   │   └── ...
│   ├── dev/
│   │   ├── config.yaml
│   │   ├── skills/
│   │   ├── memories/
│   │   └── ...
│   └── ops-manager/
│       ├── config.yaml
│       ├── skills/
│       ├── memories/
│       └── ...
└── config.yaml                    # Global Hermes config
```

### What Is Isolated

| Concern | Isolated? | Why |
|---------|-----------|-----|
| Memory | ✅ Yes | Each persona only remembers its domain |
| Skills | ✅ Yes | Skills define agent behavior — shared skills cause identity bleed |
| Tools | ✅ Yes | Dev doesn't need financial APIs; FA doesn't need build tools |
| Plugins | ✅ Yes | Plugin side effects are contained |
| Config | ✅ Yes | Each persona has unique settings (timeouts, preferences) |
| Cron jobs | ✅ Yes | Ops manager may have health-check cron that other profiles shouldn't |
| Filesystem | ⚠️ Shared | All agents share the same filesystem (Linux user). This is intentional — they need to pass files. |

### Why Shared Filesystem Is OK

The personas need to pass artifacts — a CSV of financial data, a code file, a report. Shared filesystem with **convention-based naming** prevents collisions:

```
/root/workdir/
├── requests/          # Orchestrator puts task briefs here
│   └── req-001/       # One directory per request
│       ├── brief.md
│       ├── research-output.md
│       ├── financial-data.csv
│       └── dashboard.py
├── artifacts/         # Personas write their outputs here
└── .hermes/           # Operational logs (gitignored)
```

> **Lesson learned:** Initially we tried passing data purely through message context. This failed for large outputs (code files, datasets). The shared filesystem convention with request-ID namespacing was the fix.

---

## Persona Memory Design

Memory is what makes each persona an expert, not just a tool dispatcher.

### Memory Structure

Each profile's `memories/` directory contains:

```
memories/
├── core/              # Permanent domain knowledge (seeded, never erased)
│   ├── domain.md      # What this persona knows & how it operates
│   └── constraints.md # What this persona must NEVER do
├── working/           # Session-level context (cleared between requests)
│   └── current-task.md
└── persistent/        # Cross-session learnings (accumulated over time)
    ├── preferences.md # User preferences for this domain
    └── patterns.md    # Recurring patterns and shortcuts
```

### Why Permanent vs. Working Memory Separation

This was a **lesson learned the hard way**. In early versions, all memory was session-level. After a few successful runs, the persona's memory became polluted with outdated context from previous requests.

**Fix:** Core memory is permanent and never modified during sessions. Only working and persistent memories change. Working memory is wiped between delegation requests. Persistent memory accumulates slowly via explicit save actions.

---

## Routing Table Configuration

The routing table lives in the Orchestrator's core memory and defines which persona handles which type of task.

### Current Routing Rules

| Task Pattern | Target Profile | Notes |
|-------------|---------------|-------|
| financial analysis | financial-analyst | Stock data, ratios |
| stock valuation | financial-analyst | DCF, comp analysis |
| market data | financial-analyst | Price, volume, etc. |
| research / search | research-analyst | Web research |
| fact-check | research-analyst | Verify claims |
| competitive intel | research-analyst | Market landscape |
| code / build | dev | Write/test code |
| deploy | dev | Deployment scripts |
| dashboard | dev | Visualization |
| health check | ops-manager | System status |
| recovery | ops-manager | Fix broken state |
| monitoring | ops-manager | Watch health |

### Routing Logic

Intent classification (not keyword matching). The routing table is read by the Orchestrator LLM as part of its core memory, allowing it to reason about ambiguous requests, multi-step workflows, and failure handling.

---

## Tool Access Boundaries

Each persona has a whitelist of tools it can use, configured per-profile in `config.yaml`. The principle is **least privilege** — each persona gets only what it needs.

| Tool | Orchestrator | Fin Analyst | Research Analyst | Dev | Ops Manager |
|------|-------------|-------------|------------------|-----|-------------|
| `profile_switch` | ✅ | ❌ | ❌ | ❌ | ❌ |
| `file_read` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `file_write` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `python_code_exec` | ❌ | ✅ | ❌ | ✅ | ❌ |
| `bash_exec` | ❌ | ❌ | ❌ | ✅ | ❌ |
| `web_fetch` | ❌ | ❌ | ✅ | ❌ | ❌ |
| `search` | ❌ | ❌ | ✅ | ❌ | ❌ |
| `git` | ❌ | ❌ | ❌ | ✅ | ❌ |
| `pip_install` | ❌ | ❌ | ❌ | ✅ | ❌ |
| `process_list` | ❌ | ❌ | ❌ | ❌ | ✅ |
| `health_check` | ❌ | ❌ | ❌ | ❌ | ✅ |
| `log_view` | ❌ | ❌ | ❌ | ❌ | ✅ |

### Design Rationale

- **Only the Orchestrator can switch profiles.** If a persona could switch profiles, it could impersonate other personas or read their memories.
- **Only Research Analyst has web access.** This prevents code-execution personas from downloading and running arbitrary scripts.
- **Only Ops Manager has process/system monitoring.** This prevents task personas from inspecting other processes.
- **Only Dev can install packages and run shell commands.** This is the highest-risk toolset.

---

## Error Handling & Edge Cases

### Known Failure Modes

| Failure | Symptom | Handling |
|---------|---------|----------|
| Persona timeout | No response after 120s | Retry once with simpler brief. If still fails, abort. |
| Persona hallucination | Output contains fabricated data | Validation step catches missing citations. Re-route with "cite sources explicitly." |
| Profile corruption | Persona profile config is invalid | Ops Manager detects on health check. Restore from backup. |
| Memory pollution | Persona confuses current task with past task | Working memory wiped between delegations. |
| Tool permission denied | Persona can't access needed tool | Check config.yaml for tool whitelist. |
| Filesystem collision | Two personas writing to same file | Request-ID namespacing prevents this. |

### Graceful Degradation

If a persona profile is completely unavailable (config error, missing files):

1. Orchestrator detects failure at delegation time
2. Logs to Ops Manager memory
3. Retries once after 5 seconds
4. If still failing, marks task as FAILED with diagnostic info
5. Continues with remaining tasks (partial failure)
6. Reports to user: "Could not complete [subtask description]. The [persona] agent is unavailable."

---

## Result Synthesis

Once all persona outputs are validated, the Orchestrator composes the final response.

### Composition Strategy

1. **Collect** all persona outputs with metadata (persona name, timestamp, validation status)
2. **Order** by dependency (background research first, analysis second, deliverables third)
3. **Link** cross-references (e.g., "The dashboard [Dev output] uses the financial data from [FA output section 2]")
4. **Surface confidence** — if any persona returned low-confidence results, flag them

### Validation Criteria

Common criteria per subtask:
- **Format check:** Did the output include the requested sections?
- **Data check:** Did the output include numeric data with sources?
- **Code check:** (Dev) Did the code execute without errors?
- **Citation check:** (Research) Are all claims backed by URLs?

---

## Planned Architecture

```
Internet
    ↓ HTTPS (TLS 1.3)
Caddy Reverse Proxy
    ↓
OAuth Authentication (Google/GitHub)
    ↓
Hermes Container
├── Telegram Gateway
├── Web Dashboard
└── API Gateway
    └── Monitoring & Observability
```

**Not yet implemented.** The planned architecture adds:

- **Caddy** — automated HTTPS (Let's Encrypt), reverse proxy, request filtering
- **OAuth** — authentication layer before agent access
- **Web Dashboard** — Hermes built-in dashboard behind auth
- **Monitoring** — health checks, metrics, alerting
- **Off-site backup replication** — rsync or S3-based copy of LXD snapshots to a separate location

---

## Architectural Decisions

### LXC Over Docker

**Decision:** Use LXD containers instead of Docker for the agent runtime.

**Reasoning:** Hermes interacts with filesystems, repositories, scripts, and processes like a human operator. Docker's bind-mount and volume abstractions caused confusion about filesystem boundaries during research. LXD provides:
- A complete Linux environment with natural filesystem semantics
- LXD snapshot-based backup/migration (filesystem-level, not layer-based)
- Lower abstraction overhead for tooling and debugging

### ARM-Based VPS

**Decision:** Use Oracle Cloud Ampere A1 (ARM) instances.

**Reasoning:** Free-tier availability. Agent workloads are network-bound (LLM API calls) and I/O-bound (file operations), not CPU-bound. ARM provides sufficient performance at zero compute cost.

### Dedicated GitHub Bot Account

**Decision:** Authenticate Git operations through a dedicated automation account (`johnalencar-agent`) rather than the personal account.

**Reasoning:** Limits blast radius. A dedicated bot token can be scoped and revoked independently.

### Local Secrets Over External Vault

**Decision:** Store credentials in a local filesystem secrets file (`~/.config/hermes/secrets.env`).

**Reasoning:** Simplicity for single-operator deployment. Bitwarden is available as an alternative.

### Single Profile Architecture

**Decision:** Maintain one Hermes profile with multiple specialist personas rather than separate Hermes profiles.

**Reasoning:** Personas share the same skill library, toolset, and provider configuration. Separate profiles would duplicate configuration and complicate cross-persona coordination.

### No CI/CD (Phase 1)

**Decision:** No automated CI/CD pipelines during the foundation phase.

**Reasoning:** The platform is private and single-operator. Manual git operations provide sufficient control while the architecture stabilizes.
