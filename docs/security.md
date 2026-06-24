# Security

Threat model, access controls, authentication, infrastructure isolation, network defenses, and security roadmap for the self-hosted AI agent platform.

> **Provenance:** This document was consolidated from the repository's original `docs/security.md` and the root-level `SECURITY.md` on 2026-06-24. Unique content (persona-level security, incident response, security checklist) from the root document has been merged into the appendix; the root file is now deprecated.

---

## 1. Threat Model

### 1.1 Assets

| Asset | Description | Sensitivity |
|-------|-------------|-------------|
| LLM API keys | DeepSeek + OpenRouter authentication tokens | Critical |
| GitHub PAT | Personal Access Token for `jpedroalencar/agent-env-selfhosted` | Critical |
| Telegram bot token | Bot authentication for chat interface | High |
| Hermes session DB | Conversation history and session state | High |
| Agent memory | Persistent memory files (MEMORY.md, USER.md, persona memories) | Medium |
| Git repository | Platform documentation and definitions | Medium |
| Container filesystem | All runtime state, installed software, scripts | Medium |

### 1.2 Threat Vectors

| Threat | Likelihood | Impact | Mitigation |
|--------|-----------|--------|------------|
| LLM API key leak via agent output | Low | Critical | Hermes `redact_secrets: true` auto-redacts tokens; env vars stored outside config.yaml |
| GitHub PAT leak into repo | Low | High | `.gitignore` blocks `.env`, `secrets.env`; security audit at commit time |
| Agent hallucinates destructive commands | Medium | High | LXC container isolation limits blast radius; no host access |
| LXC container breakout | Very Low | Critical | Unprivileged container; root in container maps to non-root UID on host |
| Compromised LLM provider | Very Low | High | Outbound-only networking; no sensitive data stored in prompts |
| SSH brute force (host) | Medium | Medium | Fail2Ban on host; SSH key-only auth; password auth disabled |
| Disk exhaustion (40 GB) | Medium | Medium | No automated monitoring yet; agent, session DB, and browser cache are the main consumers |
| Unauthorized Telegram access | Low | Medium | Bot token is the only auth — anyone with it can send messages |
| Credential expiry (undetected) | Medium | Low | No automated credential rotation or expiry checks |
| No off-site backup | High | Critical | Local LXD snapshots exist (retention: 7) with host validation evidence. Off-site replication is not yet configured. |

### 1.3 Assumptions

- The host is properly secured with UFW and Fail2Ban (managed independently of this document)
- SSH access to the host is restricted to authorized key holders
- Oracle Cloud's hypervisor isolation is trusted
- The LLM provider (DeepSeek) processes prompts in good faith — no secrets or credentials are sent in prompts
- This is a single-operator deployment; no multi-user access controls are in place

---

## 2. Access Control

### 2.1 Host SSH Access

- **Authentication:** SSH key pairs only (password authentication is disabled)
- **Brute force protection:** Fail2Ban monitors `/var/log/auth.log` and bans after repeated failures
- **Root login:** Disabled (`PermitRootLogin no` in `/etc/ssh/sshd_config`)
- **Management user:** The deploying user has `sudo` access

### 2.2 LXC Container Access

SSH into the host, then use `lxc exec`:

```bash
# From the host
ssh <user>@<host-ip>
lxc exec hermes-agent bash
```

No SSH daemon runs inside the container. All container management goes through LXD on the host.

### 2.3 Git Repository Access

- **Authentication:** GitHub Personal Access Token (classic PAT, `repo` scope)
- **Account:** Dedicated automation bot (`johnalencar-agent`), not the personal account
- **Token storage:** `~/.config/hermes/secrets.env` (file mode 600)
- **Token lifecycle:** Manual rotation only. When rotated, update `secrets.env` and revoke the old token in GitHub settings.

### 2.4 Telegram Access

- **Bot token:** Configured in `~/.hermes/config.yaml` under `gateway.telegram.token`
- **Redaction:** Hermes auto-redacts the token from logs and tool output
- **Chat allowlisting:** The bot responds to any chat it's added to — no explicit allowlist is configured. Restrict bot visibility at the Telegram level.

---

## 3. Authentication & Secrets Management

### 3.1 Secrets Store

All secrets are stored in a single file:

```
~/.config/hermes/secrets.env  (mode 600, root-only)
```

Current contents:

```
GITHUB_TOKEN=<token>
```

(The secrets file is owned by root and readable only by root. Only one secret is currently stored here. LLM provider API keys are not stored in this file — Hermes currently uses the provider's default API key resolution.)

### 3.2 How Secrets Are Used

```bash
# Before any Git operation, source the secrets file:
source ~/.config/hermes/secrets.env

# Git operations use the token inline (never stored in git config):
git clone "https://johnalencar-agent:${GITHUB_TOKEN}@github.com/jpedroalencar/agent-env-selfhosted.git"
```

### 3.3 Secret Protection Rules

| Rule | Enforcement |
|------|-------------|
| Never commit secrets to Git | `.gitignore` blocks `.env`, `secrets.env`, `*.env`, `.git-credentials` |
| Never send secrets in prompts | Hermes `redact_secrets: true` |
| Never store secrets in agent memory | Agent memory is scoped to domain facts only |
| Restrict file permissions | `chmod 600 ~/.config/hermes/secrets.env` |
| Back up secrets separately | Secrets are **not** in the repository — must be backed up manually |

### 3.4 Credential Rotation

**GitHub Token Rotation:**

1. Generate a new classic PAT in GitHub Settings → Developer Settings → Personal Access Tokens
2. Update the secrets file:
   ```bash
   echo "GITHUB_TOKEN=<new_token>" > ~/.config/hermes/secrets.env
   chmod 600 ~/.config/hermes/secrets.env
   ```
3. Verify the new token:
   ```bash
   source ~/.config/hermes/secrets.env
   curl -s -H "Authorization: token *** "https://api.github.com/user" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['login'])"
   ```
4. Revoke the old token in GitHub settings
5. Verify Git push still works:
   ```bash
   cd /root/agent-env-selfhosted
   git push origin main
   ```

**Telegram Bot Token Rotation:**

1. Generate a new token via @BotFather on Telegram
2. Update `~/.hermes/config.yaml`:
   ```yaml
   gateway:
     telegram:
       token: <new_bot_token>
   ```
3. Restart Hermes (`lxc restart hermes-agent`)

---

## 4. Infrastructure Isolation

### 4.1 LXD Unprivileged Container

The agent runs inside an **unprivileged LXC container**. This means:

- **UID mapping:** Root (UID 0) inside the container maps to a non-privileged UID (e.g., 1000000) on the host
- **No host access:** Container processes cannot access host resources, devices, or kernel modules
- **No escape:** Even if the agent is compromised, the attacker is inside an unprivileged container with no escalation path to the host

### 4.2 Container Boundaries

| Boundary | Implementation |
|----------|---------------|
| Process isolation | LXC cgroups — container sees only its own processes |
| Filesystem isolation | Separate root filesystem (loop device) |
| Network isolation | LXD bridge (`lxdbr0`), NAT to host |
| Device isolation | No host devices exposed to container |
| Resource limits | CPU: 2 cores, RAM: 8 GB |

### 4.3 Why LXD Instead of Docker

The "agent as a Linux user" metaphor requires a full Linux environment with natural filesystem semantics. LXD provides:

- A complete init system (Hermes runs as PID 1)
- Persistent background processes (servers, watchers)
- Snapshot-based backup (filesystem-level, not layer-based)
- No bind-mount abstraction overhead

### 4.4 Repository Isolation

- The repository contains **documentation and definitions only** — no runtime state
- `.gitignore` aggressively blocks secrets, caches, logs, memory databases, vector stores, and build artifacts
- Memory schemas are committed; runtime memory contents are never committed

---

## 5. Network Defenses

### 5.1 Current State

The container has **no inbound ports exposed**. All network communication is outbound-only.

```text
Container (outbound only)
    ↓
LXD Bridge (lxdbr0, 10.x.x.0/24)
    ↓
Host UFW Firewall
    ├── Inbound: SSH only (port 22)
    └── Outbound: Allowed (default)
    ↓
Internet
```

**Listening ports inside the container** (verified):

```
ss -tlnp
State   Recv-Q  Send-Q  Local Address:Port   Peer Address:Port
LISTEN  0       4096    127.0.0.53%lo:53     0.0.0.0:*      (systemd-resolved)
LISTEN  0       4096    127.0.0.54:53        0.0.0.0:*      (systemd-resolved)
LISTEN  0       4096    0.0.0.0:5355         0.0.0.0:*      (systemd-resolved)
LISTEN  0       4096    [::]:5355            [::]:*          (systemd-resolved)
```

Only local DNS resolver ports are listening — no external-facing services.

### 5.2 Host Firewall (UFW)

The host runs UFW with the following policy:

```bash
# Current rules (verified on host):
sudo ufw status verbose
# Default: deny (incoming), allow (outgoing)
# Allowed inbound: SSH (port 22/tcp)
```

UFW is installed on the **host only** — it is not present inside the container.

### 5.3 Host Intrusion Prevention (Fail2Ban)

Fail2Ban monitors SSH authentication logs on the host:

```bash
# Current configuration (on host):
sudo fail2ban-client status sshd
# Monitors: /var/log/auth.log
# Action: Ban IP after 5 failed attempts
# Ban time: 10 minutes (default)
# Find time: 10 minutes
```

Fail2Ban is installed on the **host only**.

### 5.4 Network Access Patterns

| Destination | Protocol | Purpose | Authentication |
|-------------|----------|---------|----------------|
| `api.deepseek.com:443` | HTTPS | LLM inference | API key in header |
| OpenRouter endpoint:443 | HTTPS | Fallback LLM | API key in header |
| `api.telegram.org:443` | HTTPS | Chat platform | Bot token in URL |
| `github.com:443` | HTTPS | Repository operations | PAT in URL |
| `hermes-agent.nousresearch.com:443` | HTTPS | Updates | None (public) |

### 5.5 TLS Configuration

All outbound connections use HTTPS (TLS 1.2 or higher). No self-signed certificates or insecure protocols are used.

---

## 6. Planned State

### 6.1 Caddy Reverse Proxy

The planned security architecture adds a public-facing access layer:

```text
Internet
    ↓ HTTPS (TLS 1.3)
Caddy Reverse Proxy
    ├── Auto HTTPS (Let's Encrypt / ACME)
    ├── Request filtering / WAF
    ├── Rate limiting
    └── Request logging
    ↓
OAuth Authentication (Google/GitHub)
    ↓
Hermes Container
    ├── Web Dashboard (behind auth)
    ├── Telegram Gateway (existing)
    └── API Gateway
```

**Not yet implemented.** Current security posture relies on no inbound ports and LXC isolation. Caddy will be introduced when the platform needs public web dashboard or API access. The Caddy proxy will run on the host (outside the container) and terminate TLS before forwarding to container services.

### 6.2 Planned Security Improvements

| Improvement | Status | Priority |
|-------------|--------|----------|
| Caddy reverse proxy + HTTPS | ⬜ Planned | High |
| OAuth authentication | ⬜ Planned | High |
| Off-site backup replication | ⬜ Planned | Medium |
| Secrets expiry monitoring | ⬜ Planned | Medium |
| TIRITH policy engine | 🔧 Available, disabled | Low |
| Web Application Firewall (WAF) | ⬜ Planned | Low |
| Multi-user access controls | ⬜ Planned | Low |

---

## 7. Security Verification Checklist

Run this after any deployment or significant configuration change:

- [ ] `ss -tlnp` — confirm no unexpected inbound ports inside container
- [ ] `ls -la ~/.config/hermes/secrets.env` — confirm mode 600, root-owned
- [ ] `cat ~/.config/hermes/secrets.env | wc -l` — confirm secrets file contains expected variables only
- [ ] `cd /root/agent-env-selfhosted && git status` — confirm working tree is clean
- [ ] `git push origin main --dry-run` — confirm push access works
- [ ] Verify `.gitignore` exists and blocks `.env`, `secrets.env`, `*.log`
- [ ] Send a test message to the Telegram bot — confirm agent responds
- [ ] Verify LXD container status from host: `lxc list` (should show `RUNNING`)

---

## Appendix: Agent-Level Security (Consolidated from Root-Level Documentation)

The following sections cover agent-level security concerns — persona isolation, data protection, credential management, known risks, incident response, and best practices. These supplement the infrastructure-level security controls in the main document.

### A.1 Security Model

The platform operates within a single Linux host, running as a single user (`root`). The primary security boundary is **profile isolation** within Hermes Agent, not OS-level sandboxing.

```
┌──────────────────────────────────────────────┐
│              Linux Host (single user)         │
│                                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │Orchestr. │  │    FA    │  │ Research │   │
│  │ Profile  │  │ Profile  │  │ Profile  │   │
│  └──────────┘  └──────────┘  └──────────┘   │
│                                               │
│  ┌──────────┐  ┌──────────┐                   │
│  │   Dev    │  │ Ops Mgr  │                   │
│  │ Profile  │  │ Profile  │                   │
│  └──────────┘  └──────────┘                   │
│                                               │
│  ┌──────────────────────────────────────┐     │
│  │     Shared Filesystem (ext4)         │     │
│  └──────────────────────────────────────┘     │
└──────────────────────────────────────────────┘
```

**Key point:** Profile isolation prevents one persona from accessing another persona's **Hermes-level data** (memories, skills, config). However, **OS-level filesystem isolation does not exist** — all personas run under the same Linux user and can theoretically read/write any file.

### A.2 Known Risks

| Risk | Severity | Description | Current Mitigation | Long-Term Fix |
|------|----------|-------------|-------------------|---------------|
| Shared filesystem (no OS isolation) | Medium | All personas share the same Linux user; any persona with shell access can read/write any file | Tool whitelisting prevents most personas from having shell access | Containerize each persona with separate Linux users |
| Prompt injection via persona output | Medium | A persona could inject instructions affecting subsequent personas via its output | Orchestrator validates output before composing next brief | Add output sanitization to strip meta-instructions |
| Unlimited persistent memory growth | Low | Persistent memory grows without bound, slowing responses and increasing hallucination risk | 50KB soft memory limit; Ops Manager can archive old entries | Implement automatic memory pruning |
| No audit trail | Medium | No centralized log of which persona processed which task or what commands were executed | Orchestrator's working memory tracks current delegation chain | Implement structured logging (JSONL) with rotation |
| No network isolation | Low (current) | Dev persona can install packages; Research can fetch arbitrary URLs | No sensitive data stored by design | Add egress filtering if platform handles sensitive data |

### A.3 Data Protection

**Sensitive data that may exist:**
- Financial analysis results (stock prices, valuations)
- Research data (market intelligence, competitive analysis)
- Generated code and reports
- No user credentials (by design)

**Storage:**
- All data lives on the local filesystem (`ext4`)
- No encryption at rest is currently applied
- Backups are unencrypted LXD snapshots and tarballs

**Data in transit:**
- The platform has no network-exposed services
- All communication is local (Hermes internal API calls between profiles)

### A.4 Credential Management Best Practices

**Principle:** No credentials in memory. The platform is designed to operate without storing credentials in persona memory.

| Service | Credential Needed? | How Provided |
|---------|-------------------|--------------|
| Yahoo Finance (yfinance) | No | Public API, no auth required |
| Web fetch | No | Public web requests |
| Git operations | No | Public repos only (HTTPS) |
| SEC EDGAR | No | Public filings, no auth required |
| Package install (PyPI) | No | Public repository |

**If credentials become necessary:**
1. Never store credentials in memory files — use environment variables
2. Never commit credentials to git — add `*.env` and `*secret*` to `.gitignore`
3. Use environment variables, not config files
4. Rotate credentials regularly
5. Audit credential usage via Ops Manager

### A.5 Incident Response

#### Classification

| Level | Description | Example | Response Time |
|-------|-------------|---------|---------------|
| **L1** | Minor | Persona returns wrong info | Next business day |
| **L2** | Moderate | Persona tool access breached | Within 4 hours |
| **L3** | Severe | Data exfiltration or system compromise | Immediate |

**L1 Procedure:**
1. Document the incident in the build log (`log/build-log.md`)
2. Fix the root cause (update memory, adjust config)
3. Verify fix with a test case

**L2 Procedure:**
1. **Contain:** Isolate the affected profile — disable tool access
2. **Assess:** Determine scope and affected data
3. **Remediate:** Fix vulnerability (adjust tool whitelist, update constraints)
4. **Verify:** Run health check and test all personas
5. **Document:** Update build log

**L3 Procedure:**
1. **Immediate containment:** Kill all Hermes processes; isolate from network
2. **Assess:** Full forensic analysis
3. **Remediate:** Restore from clean LXD snapshot
4. **Verify:** Full security audit before returning to service
5. **Document:** Detailed incident report

### A.6 Security Best Practices

**For maintainers:**
1. Run as a non-root user if possible
2. Use SSH key-based access only
3. Keep Hermes Agent updated
4. Regularly review tool access boundaries (every 3 months)
5. Validate backups — test restore from backup monthly
6. Monitor file changes with `auditd` or `inotify`

**For persona design:**
1. Principle of Least Privilege — each persona gets exactly the tools it needs
2. Data minimization — pass only necessary information in subtask briefs
3. Validate before trusting — always check outputs against criteria
4. Defense in depth — rely on tool whitelisting, core memory constraints, and output validation

**For code:**
1. No hardcoded secrets
2. Validate all inputs
3. Avoid `eval()` and `exec()`
4. Use `.gitignore` properly

### A.7 Security Checklist

Use this when adding a new persona or modifying an existing one:

- [ ] Tool whitelist configured (only necessary tools allowed)
- [ ] Core memory constraints defined (what the persona should NEVER do)
- [ ] Profile switch disabled (only Orchestrator should have this)
- [ ] Validation criteria defined for this persona's output
- [ ] No credentials or secrets in memory files
- [ ] Working memory isolation working (cleared between delegations)
- [ ] Other personas' memories are not accessible from this persona
- [ ] Documentation updated
