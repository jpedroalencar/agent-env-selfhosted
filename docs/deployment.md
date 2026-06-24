# Deployment

VPS provisioning, LXC container setup, and Hermes Agent deployment guide.

**Perspective:** This document assumes a future maintainer must rebuild the environment from scratch. Every step is documented with exact commands where applicable.

> **Provenance:** This document was consolidated from the repository's original `docs/deployment.md` and the root-level `DEPLOYMENT.md` on 2026-06-24. Unique reference content (profile configs, memory seeding templates, verification workflows) from the root document has been merged into the appendix; the root file is now deprecated.

---

## Prerequisites

- Oracle Cloud Infrastructure (OCI) account with free-tier eligibility
- SSH key pair for VPS access
- GitHub account with Personal Access Token (classic, `repo` scope)
- Telegram bot token (for chat integration)
- DeepSeek (or other LLM provider) API key

---

## 1. VPS Provisioning

### 1.1 Create Instance (Oracle Cloud Console)

1. Navigate to **Compute → Instances → Create Instance**
2. Configure:
   - **Name:** `hermes-platform`
   - **Image:** Ubuntu 24.04 LTS (aarch64)
   - **Shape:** VM.Standard.A1.Flex (ARM)
   - **vCPUs:** 2 (minimum), **Memory:** 8 GB
   - **Boot Volume:** 40 GB
   - **SSH Keys:** Add your public key

### 1.2 Initial Server Hardening

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Set hostname
sudo hostnamectl set-hostname hermes

# Configure UFW
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw enable

# Install and configure Fail2Ban
sudo apt install -y fail2ban
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo systemctl enable --now fail2ban

# Disable root SSH login and password auth
sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

---

## 2. LXD Installation and Container Setup

### 2.1 Install LXD

```bash
# Install LXD snap
sudo snap install lxd

# Initialize LXD
sudo lxd init --auto --storage-backend dir

# Add your user to the lxd group
sudo usermod -aG lxd $USER
newgrp lxd
```

### 2.2 Create Container

```bash
# Launch Debian 12 container
lxc launch images:debian/12 hermes-agent -c limits.cpu=2 -c limits.memory=8GB

# Verify container is running
lxc list

# Enter the container
lxc exec hermes-agent bash
```

### 2.3 Configure Container Networking

The container gets DHCP networking by default from LXD's managed bridge (`lxdbr0`). No inbound port forwarding is configured — all access is via `lxc exec` from the host.

```bash
# Inside the container: verify connectivity
ip addr show eth0
ping -c 3 8.8.8.8
```

---

## 3. Hermes Agent Installation

### 3.1 Inside the Container

```bash
# Update and install dependencies
apt update && apt upgrade -y
apt install -y curl git python3 python3-pip python3-venv

# Install Hermes Agent
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash

# Verify installation
hermes --version
# Expected: Hermes Agent v0.17.0 (2026.6.19)

# Available CLI toolsets
hermes tools list

# Run setup wizard
hermes setup
```

### 3.2 Provider Configuration

The setup wizard configures the primary LLM provider. For DeepSeek:

```yaml
# ~/.hermes/config.yaml
model:
  default: deepseek-v4-flash
  provider: deepseek
  base_url: https://api.deepseek.com
  fallback:
    - openrouter
    - google/gemini-2.0-flash
```

API keys are stored in a local secrets file:

```bash
# ~/.config/hermes/secrets.env
DEEPSEEK_API_KEY=sk-...
OPENROUTER_API_KEY=sk-...
```

> **Never commit secrets.env to version control.** The repository `.gitignore` explicitly excludes it.

---

## 4. Git and GitHub Integration

### 4.1 Configure Git

```bash
# Inside the container
git config --global user.name "johnalencar-agent"
git config --global user.email "johnalencar-agent@users.noreply.github.com"
```

### 4.2 GitHub Authentication

A dedicated automation account (`johnalencar-agent`) is used for all Git operations.

No tokens are embedded in remote URLs. Authentication uses **Git credential helpers** backed by the secrets file.

#### Setup credential helper (one-time)

```bash
# 1. Ensure the PAT is stored in the secrets file
#    ~/.config/hermes/secrets.env
GITHUB_TOKEN=ghp_...

# 2. Configure Git to use credential store (one-time globally)
git config --global credential.helper 'store --file ~/.config/hermes/git-credentials'

# 3. Feed credentials to the store (runs once per host)
echo "https://johnalencar-agent:${GITHUB_TOKEN}@github.com" \
  | git credential-store --file ~/.config/hermes/git-credentials approve
chmod 600 ~/.config/hermes/git-credentials
```

Git will now automatically supply the token for any operation against `github.com`.

### 4.3 Repository Setup

```bash
cd /root
git clone https://github.com/jpedroalencar/agent-env-selfhosted.git
cd agent-env-selfhosted
git config user.name "johnalencar-agent"
git config user.email "johnalencar-agent@users.noreply.github.com"
```

Authentication is automatic via the credential helper — no token in the URL.

#### Adding a new repository

1. Create the repository on GitHub
2. Add `johnalencar-agent` as a **collaborator** (Settings → Collaborators → Add people)
3. Accept the invitation (log in as `johnalencar-agent` on GitHub)
4. Clone and push normally — credential helper handles auth automatically

```bash
git clone https://github.com/jpedroalencar/<new-repo>.git
cd <new-repo>
git push origin main
# No additional authentication setup required
```

---

## 5. Telegram Integration

### 5.1 Create Telegram Bot

1. Open Telegram and message **@BotFather**
2. Send `/newbot`, follow the prompts
3. Save the bot token

### 5.2 Configure Hermes Telegram Gateway

```yaml
# ~/.hermes/config.yaml
telegram:
  reactions: false

gateway:
  telegram:
    enabled: true
    token: <BOT_TOKEN>
  platforms:
    telegram:
      extra:
        disable_topic_auto_rename: true
```

### 5.3 Restart Hermes

```bash
hermes restart
```

---

## 6. Secret Management

### 6.1 Current Approach

Secrets are stored in a local environment file at `~/.config/hermes/secrets.env`:

```bash
GITHUB_TOKEN=ghp_...
DEEPSEEK_API_KEY=sk-...
OPENROUTER_API_KEY=sk-...
```

The Hermes config.yaml references these via `$source $SECRETS_FILE` in agent context or via custom provider configuration. Source the file before using the token:

```bash
source ~/.config/hermes/secrets.env
```

### 6.2 Bitwarden Vault (Available, Not Configured)

Hermes supports Bitwarden as an alternative secret store:

```yaml
# ~/.hermes/config.yaml
secrets:
  bitwarden:
    enabled: false
    access_token_env: BWS_ACCESS_TOKEN
    project_id: ''
    cache_ttl_seconds: 300
```

TO configure, set `enabled: true`, store the Bitwarden access token in the `BWS_ACCESS_TOKEN` environment variable, and set the project ID.

---

## 7. Recovery Procedures

### 7.1 Container Snapshot

```bash
# From the host
sudo /usr/local/bin/backup-container.sh

# Or manually with a custom name:
lxc snapshot hermes-agent snapshot-$(date +%Y%m%d)

# List snapshots (requires lxc info on LXD 5.21+):
lxc info hermes-agent | grep -A 20 '^Snapshots:'
```

### 7.2 Container Restoration

From a backup snapshot:

```bash
# Interactive restore (lists available snapshots, prompts for selection)
# From the host:
sudo /usr/local/bin/restore-container.sh

# Direct restore (specify snapshot name):
sudo SNAPSHOT_NAME=backup-20260623-190808 /usr/local/bin/restore-container.sh
```

Recover from scratch (no snapshot available):

```bash
# From the host:
lxc delete hermes-agent
lxc launch images:debian/12 hermes-agent -c limits.cpu=2 -c limits.memory=8GB
# Re-run deployment steps 2.3 through 6
```

### 7.3 Backup Evidence

After every successful backup, a host validation evidence artifact is injected into the container's repository:

```bash
# Inside the container, verify the latest backup evidence:
ls -t artifacts/operations-manager/host-validation/backup-evidence-*.md | head -1
# Read it:
cat artifacts/operations-manager/host-validation/backup-evidence-*.md
# Expected: backup_result: "success", status: "verified"
```

The evidence artifact confirms the backup was created, verified, and had retention applied — without requiring host-side inspection.

### 7.4 Repository as Single Source of Truth

The `agent-env-selfhosted` GitHub repository is the authoritative reference for platform documentation. After a fresh deployment:

```bash
cd /root
git clone "https://johnalencar-agent:${GITHUB_TOKEN}@github.com/jpedroalencar/agent-env-selfhosted.git"
```

All documented procedures, configurations, and architecture decisions live in the repository — not in ephemeral container state.

### 7.5 What Is Not Recoverable From The Repository

- **API keys and tokens** — stored in `~/.config/hermes/secrets.env` only
- **Hermes session history** — stored in the local session database
- **Runtime memory** — stored in `~/.hermes/memories/`
- **Content artifacts** — stored in `~/.hermes/content/`
- **Cron job state** — stored in `~/.hermes/cron/`

These must be backed up separately or re-created after recovery.

---

## 8. Verification Checklist

After deployment, verify:

- [ ] `hermes --version` shows expected version
- [ ] `source ~/.config/hermes/secrets.env && echo $GITHUB_TOKEN` returns a token
- [ ] Telegram bot responds to messages
- [ ] LLM provider responds (send a test message)
- [ ] GitHub clone succeeds with token auth
- [ ] Git user name and email are configured
- [ ] `.gitignore` excludes secrets, runtime state, and build artifacts
- [ ] Repository push/pull works without credential prompt
- [ ] Backup script runs successfully: `sudo /usr/local/bin/backup-container.sh` (dry-run from host)
- [ ] Host validation evidence is visible: `ls artifacts/operations-manager/host-validation/backup-evidence-*.md` (inside container)

---

## Appendix: Profile Templates and Memory Seeding

The following sections were consolidated from the original root-level `DEPLOYMENT.md`.

### A.1 Profile Config Templates

Each persona needs a `config.yaml` in its profile directory.

**Financial Analyst (`~/.hermes/profiles/financial-analyst/config.yaml`):**
```yaml
persona:
  name: "Financial Analyst"
  role: "Financial data analysis and valuation"
  never_do: "Never fabricate financial data. Always cite sources."
tools:
  allowed:
    - python_code_exec
    - file_write
    - file_read
  blocked:
    - bash_exec
    - web_fetch
    - profile_switch
    - pip_install
memory:
  max_size_kb: 50
  auto_clean: true
```

**Research Analyst (`~/.hermes/profiles/research-analyst/config.yaml`):**
```yaml
persona:
  name: "Research Analyst"
  role: "Web research and fact-checking"
tools:
  allowed:
    - web_fetch
    - search
    - file_read
    - file_write
  blocked:
    - bash_exec
    - python_code_exec
    - profile_switch
    - pip_install
memory:
  max_size_kb: 50
  auto_clean: true
```

**Dev (`~/.hermes/profiles/dev/config.yaml`):**
```yaml
persona:
  name: "Dev"
  role: "Code writing, testing, and deployment"
tools:
  allowed:
    - python_code_exec
    - bash_exec
    - git
    - pip_install
    - file_read
    - file_write
  blocked:
    - web_fetch
    - profile_switch
memory:
  max_size_kb: 50
  auto_clean: true
```

**Ops Manager (`~/.hermes/profiles/ops-manager/config.yaml`):**
```yaml
persona:
  name: "Operations Manager"
  role: "Health monitoring, recovery, and diagnostics"
tools:
  allowed:
    - process_list
    - health_check
    - log_view
    - file_read
  blocked:
    - bash_exec
    - python_code_exec
    - web_fetch
    - profile_switch
    - pip_install
    - file_write
memory:
  max_size_kb: 50
  auto_clean: true
```

### A.2 Core Memory Templates

**Financial Analyst — `constraints.md`:**
```markdown
# Financial Analyst Constraints

## NEVER
- Fabricate financial data. Always cite sources.
- Access other profiles' memory or configuration.
- Execute shell commands.
- Access the web (leave web research to Research Analyst).
- Make investment recommendations without clearly stating methodology.

## ALWAYS
- Cite the source of every data point.
- State when data is unavailable rather than making assumptions.
- Use yfinance for market data when possible.
- Present financial data with appropriate context (time period, currency).
```

**Dev — `constraints.md`:**
```markdown
# Dev Constraints

## NEVER
- Hardcode credentials or secrets in code.
- Execute code without testing it first.
- Access other profiles' memory or configuration.
- Download or run arbitrary code from the internet.
- Modify system configuration files.

## ALWAYS
- Test code before declaring it complete.
- Document all dependencies (requirements.txt or equivalent).
- Use version control for code changes.
- Follow Python best practices (PEP 8).
```

### A.3 Orchestrator Routing Memory Template

`~/.hermes/profiles/orchestrator/memories/core/routing.md`:
```markdown
# Routing Table

Route subtasks based on intent classification:

## Financial Analysis → financial-analyst
- Stock valuation, P/E ratio, market cap
- Financial statement analysis
- DCF, comparable company analysis
- Financial ratios and KPIs
- Data source: yfinance, SEC EDGAR

## Web Research → research-analyst
- Company research, industry analysis
- Fact-checking, claim verification
- News summarization, competitive intelligence

## Code & Development → dev
- Writing and testing code
- Building dashboards and visualizations
- Deployment scripts

## Operations → ops-manager
- Health checks and monitoring
- Recovery procedures
- Diagnostics and troubleshooting

## Default
- If intent is unclear, ask the user for clarification.
- Never attempt domain work yourself — always delegate.
```

### A.4 Verification Workflow Test

```bash
# Run a complete orchestration workflow:
hermes run --profile orchestrator --command \
  "Run a test workflow: research Apple Inc. (AAPL), fetch its current P/E ratio, and return a brief summary."
```

**Expected outcome:**
1. Orchestrator decomposes the request
2. Routes "research Apple" to Research Analyst
3. Routes "fetch P/E ratio" to Financial Analyst
4. Both personas complete their tasks
5. Orchestrator composes a summary
6. Summary is returned

**If this fails:**
- Check each persona's tool access
- Verify memory is seeded correctly
- Check the Orchestrator's routing memory
