# Diagram Notes

Assumptions, trust boundary definitions, component responsibilities, and external dependency notes for the platform architecture diagrams.

**Source files:**
- `diagrams/current-architecture.md` — Mermaid diagram (for review before SVG export)
- `diagrams/current-architecture.drawio` — Canonical editable source (Draw.io / diagrams.net)

---

## 1. Diagram Assumptions

### 1.1 Scope

- Diagrams represent only the **currently deployed and operational** architecture
- All external services are depicted as they are consumed — not as full systems

### 1.2 Network

- All outbound traffic from the container traverses LXD bridge NAT (`lxdbr0`) to the host network
- The host has a public IP on its external interface; the container uses private addressing behind NAT
- DNS resolution goes through systemd-resolved inside the container (not shown in diagrams for clarity)
- All HTTPS connections use TLS 1.2 or higher

### 1.3 Authentication

- API keys and tokens authenticate the container to external services — not the other way
- The agent never receives inbound connections from external services (no webhooks)
- Telegram uses long-polling or webhook polling (not shown) — no incoming connections
- Git operations are SSH-equivalent via HTTPS with token auth

### 1.4 Host Configuration

- UFW and Fail2Ban run on the host only, inside the container they are absent
- The host manages its own SSH access, security updates, and system administration independently
- The host kernel is 6.17.0-1011-oracle (OCI-optimized) running Ubuntu 24.04 LTS

---

## 2. Trust Boundary Definitions

### 2.1 OCI Hypervisor Boundary

| Property | Value |
|----------|-------|
| Trust level | **Trusted** (cloud provider) |
| Type | Oracle Cloud Infrastructure hypervisor |
| What it isolates | Guest VPS from other tenants |
| Assumption | OCI's hypervisor and physical infrastructure security are competent |
| Risk | Hypervisor breakout (Very Low) — accepted as inherited risk |

### 2.2 VPS Host Boundary

| Property | Value |
|----------|-------|
| Trust level | **Trusted Infrastructure** |
| Components | Ubuntu 24.04 LTS, UFW, Fail2Ban, LXD |
| What it contains | LXC container, host filesystem, kernel, network stack |
| Access | SSH only (key auth), password disabled, root login disabled |
| Defenses | UFW (inbound SSH only), Fail2Ban (SSH brute-force) |

### 2.3 LXD Unprivileged Container Boundary

| Property | Value |
|----------|-------|
| Trust level | **Strong Isolation** |
| Type | Unprivileged LXC (UID remapped) |
| What it contains | Hermes Agent, runtime storage, personas, skills |
| What it prevents | Container root → host root escalation |
| Network | Outbound-only — no inbound ports exposed |
| Resource limits | 2 vCPU, 8 GB RAM, 40 GB disk |
| Access method | `lxc exec` from host only (no SSH inside container) |

### 2.4 Key Implication of These Boundaries

```
Host compromise → Container compromised (host controls LXD)
Container compromise → Host NOT compromised (unprivileged container)
```

This asymmetry is intentional. The agent has full control inside the container but zero ability to affect the host.

---

## 3. Component Responsibilities

### 3.1 Hermes Agent (v0.17.0)

| Role | Detail |
|------|--------|
| Init process | PID 1 inside container |
| LLM orchestration | Routes prompts to primary (DeepSeek) or fallback (OpenRouter) |
| Tool execution | Web search, browser, terminal, file ops, code execution, vision |
| Skill loading | Loads and executes skill definitions |
| Persona routing | Delegates specialist tasks via `delegate_task` |
| Memory management | Reads/writes MEMORY.md, USER.md, persona memories |
| Git operations | Executes git commands via terminal tool |
| Secret sourcing | Sources `secrets.env` before Git operations |

### 3.2 Specialist Personas

| Persona | Responsibility | Activation |
|---------|---------------|------------|
| Orchestrator | Coordination, routing, decisions | Default (always active) |
| Financial Analyst | Stocks, ETFs, valuation, earnings | Delegated by Orchestrator |
| Research Analyst | Deep research, intel, analysis | Delegated by Orchestrator |
| Dev | Code, infrastructure, automation | Delegated by Orchestrator |
| Operations Manager | Planning, docs, project mgmt | Delegated by Orchestrator |

Each persona has a SKILL.md definition, a workspace directory, and a dedicated memory file, but they are not separate processes — they are loaded contexts within Hermes.

### 3.3 Skills & Tools

- **73 installed skills** across 15 categories (autonomous-ai-agents, creative, data-science, email, github, media, mlops, note-taking, personas, productivity, research, smart-home, social-media, software-development, devops)
- **Enabled toolsets:** web, browser, terminal, file, code_execution, vision, image_gen
- **Disabled:** video, video_gen

### 3.4 Runtime Storage

| Store | Location | Content | Git-ignored |
|-------|----------|---------|-------------|
| Session database | `~/.hermes/` (internal) | Conversation history | Yes |
| Agent memory | `~/.hermes/memories/MEMORY.md` | Agent's personal notes | Yes |
| User profile | `~/.hermes/memories/USER.md` | User preferences and identity | Yes |
| Persona memories | `~/.hermes/personas/*/memory.md` | Per-persona knowledge | Yes |
| Content storage | `~/.hermes/content/` | Generated reports and artifacts | Yes |

---

## 4. External Dependencies

### 4.1 DeepSeek API

| Property | Value |
|----------|-------|
| Endpoint | `https://api.deepseek.com` |
| Model | `deepseek-v4-flash` |
| Role | Primary LLM inference |
| Auth | API key in HTTPS header |
| Outage impact | Agent cannot respond. Fallback activates automatically |
| Rate limit | Unknown — 429 responses fall back to OpenRouter |

### 4.2 OpenRouter API (Fallback)

| Property | Value |
|----------|-------|
| Endpoint | OpenRouter router |
| Model | `google/gemini-2.0-flash` |
| Role | Fallback LLM inference |
| Auth | API key in HTTPS header |
| Feature | Response caching (300s TTL) |
| Activation | When DeepSeek returns errors or 429 |

### 4.3 Telegram Bot API

| Property | Value |
|----------|-------|
| Endpoint | `https://api.telegram.org` |
| Role | Chat interface |
| Auth | Bot token in URL or header |
| Outage impact | Agent unreachable. Logs still capture any CLI activity |
| Model | Long-polling or webhook (Hermes internal) |

### 4.4 GitHub API

| Property | Value |
|----------|-------|
| Endpoint | `https://github.com` and `https://api.github.com` |
| Role | Repository operations (clone, push, PR, issues) |
| Auth | PAT (`johnalencar-agent` account) |
| Outage impact | Git operations fail. Agent continues on other tasks |
| Scope | `repo` — limited to `jpedroalencar/agent-env-selfhosted` |

---

## 5. Terminology Consistency Map

Ensuring all diagram assets use the same terms as the documentation:

| Diagram Label | Documentation Reference |
|---------------|------------------------|
| Oracle Cloud VPS — Ubuntu 24.04 LTS | docs/architecture.md §Host Layer |
| LXD Unprivileged Container — Debian 12 | docs/architecture.md §Container Layer |
| Hermes Agent v0.17.0 | docs/architecture.md §Agent Layer |
| DeepSeek API (deepseek-v4-flash) | docs/configuration.md §2.1 |
| OpenRouter API (google/gemini-2.0-flash) | docs/configuration.md §2.2 |
| Telegram Bot API | docs/configuration.md §1.4 |
| GitHub API (johnalencar-agent) | docs/security.md §2.3 |
| UFW Firewall | docs/security.md §5.2 |
| Fail2Ban | docs/security.md §5.3 |
| secrets.env | docs/security.md §3.1 |
| config.yaml | docs/configuration.md §1.1 |
| Session Database | docs/architecture.md §Storage Layout |
| Agent Memory | docs/architecture.md §Storage Layout |
| Specialist Personas | docs/architecture.md §Persona Architecture |
| Financial Analyst / Research Analyst / Dev / OM | Persona skill definitions in SKILL.md |
| Outbound-only network | docs/security.md §5.1 |
| LXD UID remapped isolation | docs/security.md §4.1 |
| API Key / Bot Token / PAT auth | docs/security.md §3.3 |

---

## 6. SVG Export Notes

When exporting these diagrams to SVG:

1. **Mermaid → SVG:** Use the Mermaid CLI (`mmdc`) or a Mermaid live editor:
   ```bash
   mmdc -i diagrams/current-architecture.md -o diagrams/current-architecture.svg -t dark
   ```
   The `.md` file contains three separate diagrams. Export individually or render the trust boundary graph (third section) as the primary architecture view.

2. **Draw.io → SVG:** Open `diagrams/current-architecture.drawio` in the diagrams.net editor, then File → Export → SVG. Enable "Include a copy of my diagram" for future editing.

3. **Do not commit SVGs** until after manual review per the project convention.
