# Build Log

Engineering decisions, lessons learned, and project milestones.

---

## 2026-06-23 — Repository Initialization

### Decision
Create `agent-env-selfhosted` as the single source of truth for platform documentation, configuration, and operational procedures.

### Reasoning
The platform was operating with no persistent documentation outside the Hermes agent's ephemeral memory and conversation history. When the agent is reset or a session is closed, infrastructure decisions are lost. A GitHub repository provides:
- Version-controlled documentation that survives container rebuilds
- A structured reference for future maintainers
- A pattern for the agent to document its own platform (dogfooding)

### Lessons Learned
- The repository boundary must be clearly defined: documentation and *definitions* go in, runtime *state* stays out
- The `.gitignore` must be aggressive from day one — retroactively removing committed secrets is difficult
- Memory protection rules (no runtime memory, no embeddings, no conversation history) must be enforced at commit time

---

## 2026-06-23 — Security-First Repository Structure

### Decision
Scaffold the repository with strict `.gitignore` rules, placeholder documentation only, and no substantive code in the first commit.

### Reasoning
Repository security is easier to establish on day one than to retrofit. The first commit establishes:
- A comprehensive `.gitignore` blocking secrets, credentials, caches, logs, runtime memory, vector stores, and build artifacts
- A directory structure that separates documentation (`docs/`), definitions (`agent/`), and runtime state (`workspaces/`, `logs/`)
- Placeholder documentation files (header-only) that will be populated in subsequent commits

### Lessons Learned
- .gitignore sections should be organized by category (Secrets, Cache, Environments, etc.) for maintainability
- Even placeholder `.md` files should have clear comments indicating their intended content
- `.gitkeep` files are necessary to preserve empty directory structure in Git

---

## 2026-06-23 — LXC Over Docker for Agent Runtime

### Decision
Use LXD containers instead of Docker for the Hermes Agent runtime environment.

### Reasoning
During initial research, Hermes was tested in Docker containers. Several issues emerged:
1. **Filesystem confusion:** Docker's bind-mount and volume abstractions created confusion about where files actually lived. Hermes navigates directories like a human operator — symlinks, mount points, and volume boundaries were a recurring source of tool errors.
2. **Process management:** Background processes (servers, watchers) need persistent process tracking. Docker's container lifecycle model (start/stop/restart) is poorly suited for agents that spawn and manage long-lived processes.
3. **Backup simplicity:** LXD snapshots capture the entire filesystem state atomically, with no need to coordinate multiple volumes or container layers.

LXD provides a complete Linux environment with natural filesystem semantics, snapshot-based backup, and strong isolation — all without the abstraction overhead of Docker.

### Lessons Learned
- The "agent as a Linux user" metaphor is more accurate than "agent as a web service"
- Container runtime choice has significant operational implications — Docker is not always the right answer
- LXD unprivileged containers provide better security isolation than default Docker configurations

---

## 2026-06-23 — Dedicated GitHub Automation Account

### Decision
Create a dedicated GitHub account (`johnalencar-agent`) for all automated Git operations, rather than using the personal account's credentials.

### Reasoning
1. **Blast radius:** A leaked PAT (Personal Access Token) on the agent account only compromises repository access, not personal account access
2. **Auditability:** Commits from the automation account are clearly distinguishable from human commits
3. **Credential lifecycle:** The automation token can be rotated without affecting personal access
4. **Scope limitation:** The automation account has `repo` scope access only to the `agent-env-selfhosted` repository

### Lessons Learned
- GitHub fine-grained PATs (organization-level) provide better scope control than classic PATs
- The token must be stored outside the repository and outside the Hermes session database
- `git config user.email` should use the `users.noreply.github.com` format for the automation account

---

## 2026-06-23 — Local Secret Store (Environment File)

### Decision
Store API keys and tokens in a local `secrets.env` file sourced at runtime, rather than in Hermes config or an external vault.

### Reasoning
1. **Simplicity:** For a single-operator private deployment, a sourced env file is the simplest secure approach
2. **Separation:** Secrets are kept out of `config.yaml` (which is documented and may be shared), out of environment variables (which appear in process listings), and out of the repository
3. **Hermes compatibility:** The `hermes` config supports provider API keys through environment variables and custom provider configuration

### Caveats
- This is not suitable for multi-user or public deployments
- Bitwarden is available as an alternative in the Hermes config (`secrets.bitwarden`) but not yet configured
- The secrets file must be backed up separately — it is not in version control

### Lessons Learned
- Never commit `.env` or `secrets.env` to Git — the `.gitignore` must block these patterns by default
- A single secrets file is manageable for 3-5 variables but becomes unwieldy beyond that
- Future migration to Bitwarden or another secret management system is advisable for production

---

## 2026-06-23 — Single Hermes Profile with Persona Architecture

### Decision
Run all agent activity under one Hermes profile with specialist personas routed by an Orchestrator, rather than creating separate Hermes profiles per role.

### Reasoning
1. **Shared configuration:** All personas use the same provider, model, skills, and tools. Separate profiles would duplicate configuration.
2. **Cross-persona coordination:** The Orchestrator needs to hand off work between FA, RA, Dev, and OM. This is impossible if each runs in an isolated profile.
3. **Session continuity:** Conversations span multiple persona interactions. A single profile preserves conversation history across handoffs.
4. **Skills and tools:** 73 skills are shared across all personas. Duplicating this per-profile is wasteful.

### Persona Design
Each persona is implemented as:
- A **SKILL.md** defining identity, role boundaries, and workflow rules
- A **workspace** directory for output files
- A **dedicated memory file** for persona-specific persistent knowledge

The Orchestrator maintains a routing table matching natural-language triggers and slash commands to personas.

### Lessons Learned
- Strict role boundaries are essential — without them, personas blur into a general-purpose agent
- Persona memory must be scoped to domain-specific facts only (stocks for FA, code for Dev, etc.)
- Delegation depth (`max_spawn_depth: 1`) prevents runaway subagent chains

---

## 2026-06-23 — ARM Architecture for VPS

### Decision
Use Oracle Cloud Ampere A1 (ARM) instances rather than x86.

### Reasoning
- **Cost:** Free-tier eligibility (up to 4 cores, 24 GB RAM across instances)
- **Workload fit:** Agent workloads are network-bound (LLM API calls) and I/O-bound (file operations), not CPU-bound. ARM Neoverse-N1 provides sufficient performance.
- **Container compatibility:** LXD and Debian 12 run natively on aarch64 with no issues. Hermes Agent is Python-based and ARM-compatible.

### Lessons Learned
- All tooling (Hermes, Python, Git, LXD) works identically on ARM — no compatibility surprises
- The main limitation is Docker image availability for ARM, but the LXD-based architecture avoids this entirely
- Oracle Cloud ARM instances have been stable throughout the foundation phase

---

## 2026-06-23 — Outbound-Only Container Networking

### Decision
The Hermes container has no inbound ports — all communication is initiated from within the container.

### Reasoning
- **Security:** No attack surface exposed by the container. Even if the container is compromised, there's no port to exploit from outside.
- **Agent access:** The agent connects to external APIs (DeepSeek, Telegram, GitHub) — these are outbound connections only.
- **Host firewall:** UFW on the host blocks all inbound except SSH, providing defense in depth.

### Trade-off
- Direct shell access requires `lxc exec` from the host — no SSH into the container
- Public web dashboard and API access (planned for Phase 2) will require inbound proxy configuration
- Debugging from outside the host requires host SSH access first

### Lessons Learned
- Outbound-only is the safest default for an agent runtime
- The host serves as a jump box for container management — this is acceptable for single-operator deployment
- Planned Caddy proxy will handle inbound traffic with proper authentication, maintaining container isolation
