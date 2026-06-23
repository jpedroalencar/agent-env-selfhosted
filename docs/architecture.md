# Architecture

System architecture and design decisions for the self-hosted AI agent platform.

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
│       ├── Local Secret Store (/root/.config/hermes/secrets.env)
│       └── Python 3.11.2 Runtime
└── 40 GB Boot Volume (loop device)
```

### Host Layer

- **Provider:** Oracle Cloud Infrastructure (OCI), free-tier Ampere A1 instance
- **CPU:** 2× Neoverse-N1 (ARM aarch64) @ ~3.0 GHz
- **RAM:** 8 GB
- **Kernel:** 6.17.0-1011-oracle (Oracle Linux compatible kernel on host)
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
- **Skills:** 73 built-in skills across 15 categories
- **Tools:** web search, browser automation, terminal, file ops, code execution, vision, delegation

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

## Planned Architecture

```text
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
- **Automated Backups** — scheduled snapshots and off-site replication

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

**Reasoning:** Free-tier availability. Agent workloads are network-bound (LLM API calls) and I/O-bound (file operations), not CPU-bound. ARM provides sufficient performance at zero compute cost for these workloads.

### Dedicated GitHub Bot Account

**Decision:** Authenticate Git operations through a dedicated automation account (`johnalencar-agent`) rather than the personal account.

**Reasoning:** Limits blast radius. A dedicated bot token can be scoped and revoked independently. The agent never has access to personal account credentials.

### Local Secrets Over External Vault

**Decision:** Store credentials in a local filesystem secrets file (`~/.config/hermes/secrets.env`).

**Reasoning:** Simplicity for single-operator deployment. Bitwarden is available as an alternative in the Hermes config but not yet configured. This decision will be revisited when the platform gains multi-user access or public exposure.

### Single Profile Architecture

**Decision:** Maintain one Hermes profile with multiple specialist personas rather than separate Hermes profiles.

**Reasoning:** Personas share the same skill library, toolset, and provider configuration. Separate profiles would duplicate configuration and complicate cross-persona coordination. The Orchestrator persona handles routing and coordination between specialist agents.

### No CI/CD (Phase 1)

**Decision:** No automated CI/CD pipelines during the foundation phase.

**Reasoning:** The platform is private and single-operator. Manual git operations provide sufficient control while the architecture stabilizes. CI/CD will be introduced when the platform needs to manage multiple environments (staging, production, public demo).
