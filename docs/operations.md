# Operations

Maintainer runbook for the self-hosted AI agent platform. All commands assume you are inside the Hermes LXC container unless marked otherwise.

---

## 1. Prerequisites

### 1.1 Accessing the Container

All container management goes through the **host**:

```bash
# Step 1: SSH to the host
ssh <user>@<host-ip>

# Step 2: Enter the Hermes container
lxc exec hermes-agent bash
```

You are now inside the Debian 12 container as root. All commands in this runbook (unless explicitly marked `# host:`) run inside the container.

### 1.2 Verify You Are in the Right Place

```bash
# Check hostname (should be 'hermes')
hostname

# Check it's the right container (Debian 12)
cat /etc/os-release | grep PRETTY_NAME
# Expected: PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"

# Verify Hermes is PID 1
cat /proc/1/cmdline | tr '\0' ' '
# Expected output includes '/usr/local/bin/hermes'
```

---

## 2. Standard Operating Procedures

### 2.1 Start Hermes

Hermes runs as **PID 1** inside the container. Starting Hermes means starting the container itself:

```bash
# host: Start the container (also starts Hermes as init)
lxc start hermes-agent

# host: Verify it's running
lxc list
# Expected: hermes-agent | RUNNING | ...

# Inside the container: verify Hermes process
ps aux | grep hermes
# Expected: root /usr/local/bin/hermes (PID 1)
```

### 2.2 Stop Hermes

```bash
# Graceful shutdown
# host:
lxc stop hermes-agent

# Force stop if graceful shutdown hangs (wait 30s first)
lxc stop hermes-agent --force
```

### 2.3 Restart Hermes

```bash
# host: Restart the container (cold restart — Hermes restarts as PID 1)
lxc restart hermes-agent

# Wait for Hermes to initialize (~10-15 seconds), then verify:
# host:
lxc exec hermes-agent -- ps aux | grep hermes
```

### 2.4 Check Status

```bash
# host: Container status
lxc list hermes-agent
# Expected: RUNNING

# Inside: Hermes process status
ps aux | grep hermes
# Expected: /usr/local/bin/hermes as PID 1

# Inside: Uptime
uptime
```

### 2.5 Inspect and Tail Application Logs

All Hermes logs are in `/root/.hermes/`:

```bash
# Primary log files:
# ─────────────────────────────────────────────
ls -lh /root/.hermes/*.log

# Most important:
#   agent.log   — Main agent activity log
#   errors.log  — Error events (check this first when troubleshooting)
#   gateway.log — Telegram gateway communication
#   update.log  — Update activity (hermes update)

# Tail the agent log (live follow):
tail -f /root/.hermes/agent.log

# Tail the error log:
tail -f /root/.hermes/errors.log

# Tail the gateway log:
tail -f /root/.hermes/gateway.log

# Check the last N lines of a specific log:
tail -50 /root/.hermes/agent.log

# Search logs for specific events:
grep -i error /root/.hermes/agent.log | tail -20
grep -i "rate limit\|429\|timeout" /root/.hermes/errors.log

# Check log sizes (growing logs may indicate a problem):
du -sh /root/.hermes/*.log | sort -rh

# Log rotation: Hermes manages logs internally. Manual cleanup if needed:
# Truncate a single log (preserve the file, empty the contents):
truncate -s 0 /root/.hermes/agent.log
```

**What to look for in logs:**
- `ERROR` — unexpected failures requiring investigation
- `429` or `rate_limit` — LLM provider rate limiting (check provider status)
- `timeout` — API call timeouts (network or provider issue)
- `Traceback` — Python exceptions (usually configuration issues)
- `ConnectionError` — Network connectivity problems

### 2.6 Update Hermes

```bash
# Step 1: Check for available updates
hermes --version
# Look for: "Update available: N commits behind — run 'hermes update'"

# Step 2: Read the changelog before updating
hermes update --dry-run   # Preview what will change

# Step 3: Take a container snapshot (host)
# host:
lxc snapshot hermes-agent pre-update-$(date +%Y%m%d)

# Step 4: Run the update
hermes update

# Step 5: Verify the update
hermes --version

# Step 6: Send a test message to confirm the agent responds
```

### 2.7 Recover from a Failed Update

If Hermes fails to start after an update:

```bash
# Step 1: Check the error log
cat /root/.hermes/errors.log | tail -30
cat /root/.hermes/update.log

# Step 2: If the container is still running but Hermes is broken:
#   — Restore the snapshot from the host (this replaces the filesystem)
#   host:
lxc restore hermes-agent pre-update-20260623
lxc start hermes-agent

# Step 3: If the container won't start at all:
#   — Hard restore from the host
#   host:
lxc stop hermes-agent --force
lxc restore hermes-agent pre-update-20260623
lxc start hermes-agent

# Step 4: Verify rollback
lxc exec hermes-agent -- hermes --version

# Step 5: Report the failed version and error to upstream
```

### 2.8 Rotate GitHub Token

See [Security: Credential Rotation](/docs/security.md#34-credential-rotation) for the full procedure.

Quick reference:

```bash
# 1. Update the token in secrets.env
echo 'GITHUB_TOKEN=<new_token>' > ~/.config/hermes/secrets.env
chmod 600 ~/.config/hermes/secrets.env

# 2. Verify the new token
source ~/.config/hermes/secrets.env
curl -s -H "Authorization: token *** "https://api.github.com/user" | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['login'])"
# Expected: johnalencar-agent

# 3. Test Git push
cd /root/agent-env-selfhosted
git push origin main

# 4. Revoke the old token in GitHub Settings → Developer Settings → PAT
```

### 2.9 Verify GitHub Access

```bash
# Test authentication
source ~/.config/hermes/secrets.env
curl -s -H "Authorization: token *** "https://api.github.com/user" | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(f'User: {d[\"login\"]}'); print(f'Scope: {d.get(\"plan\",{}).get(\"name\",\"classic PAT\")}')"

# Test repository access
curl -s -H "Authorization: token *** "https://api.github.com/repos/jpedroalencar/agent-env-selfhosted" | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Push: {d[\"permissions\"][\"push\"]}'); print(f'Pull: {d[\"permissions\"][\"pull\"]}')"
# Expected: Push: True, Pull: True

# Test Git push
cd /root/agent-env-selfhosted
git push origin main --dry-run
# Expected: Everything up-to-date
```

### 2.10 Check Disk Usage

```bash
# Overall disk usage
df -h /
# Expected: ~33 GB available out of 40 GB

# Largest directories
du -sh /root/.hermes/* /root/* 2>/dev/null | sort -rh | head -15

# Specific space consumers:
#   ~/.hermes/          — logs, config, memories, session DB
#   ~/.hermes/content/  — agent-generated artifacts
#   /tmp/               — temporary files
#   /var/log/           — system logs

# Clean up if disk is low:

# Truncate Hermes logs (safe — Hermes recreates them):
truncate -s 0 /root/.hermes/*.log

# Clean package cache:
apt clean

# Remove old apt cached packages:
apt autoremove --purge -y

# Clean journal logs (if systemd-journald is active):
journalctl --vacuum-time=7d
```

### 2.11 Verify Network Connectivity

```bash
# Test basic connectivity
ping -c 3 8.8.8.8

# Test DNS resolution
nslookup api.deepseek.com
nslookup api.telegram.org
nslookup github.com

# Test HTTPS connectivity (DeepSeek)
curl -s -o /dev/null -w "%{http_code}" "https://api.deepseek.com"

# Test HTTPS connectivity (GitHub)
curl -s -o /dev/null -w "%{http_code}" "https://github.com"

# Test Telegram connectivity
curl -s -o /dev/null -w "%{http_code}" "https://api.telegram.org"

# Check active connections
ss -tnp | grep ESTAB
```

### 2.12 Test LLM Provider

```bash
# Send a minimal test prompt to DeepSeek
source ~/.config/hermes/secrets.env
curl -s -X POST "https://api.deepseek.com/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
  -d '{
    "model": "deepseek-v4-flash",
    "messages": [{"role": "user", "content": "Say hello in one word."}],
    "max_tokens": 10
  }' | python3 -m json.tool | head -10
```

---

## 3. Emergency Procedures

### 3.1 Container Unresponsive

```bash
# host: Check if container is responding
lxc info hermes-agent

# host: Force restart if hung
lxc stop hermes-agent --force
lxc start hermes-agent

# host: If container won't start, check logs
lxc info hermes-agent --show-log
```

### 3.2 Disk Full

```bash
# If you can still get a shell:
# 1. Immediately truncate Hermes logs
truncate -s 0 /root/.hermes/*.log

# 2. Clean package cache
apt clean && apt autoremove --purge -y

# 3. Remove old snapshots (host)
# host:
lxc delete hermes-agent/pre-update-20260623

# 4. Verify freed space
df -h /

# If you cannot get a shell, extend the disk from Oracle Cloud console
# and resize the filesystem (host):
# host:
lxc exec hermes-agent -- resize2fs /dev/sda1
```

### 3.3 Credential Compromise

If you suspect a credential has been leaked:

```bash
# 1. Revoke immediately (from any machine with browser access):
#    GitHub: Settings → Developer Settings → Personal Access Tokens → Revoke
#    Telegram: @BotFather → /mybots → select bot → API Token → Revoke

# 2. Generate new credentials and update secrets.env
#    (see section 2.8 — Rotate GitHub Token and security.md §3.4)

# 3. Rotate ALL secrets, not just the compromised one
#    (if one token was leaked, others may have been exposed through the same vector)

# 4. Audit logs for unauthorized access
grep -i "error\|fail\|denied" /root/.hermes/errors.log | tail -20

# 5. If the repo was accessed, check the audit log on GitHub:
#    github.com/jpedroalencar/agent-env-selfhosted → Insights → Audit Log
```

### 3.4 Complete Container Loss

If the container is irrecoverable (filesystem corruption, deleted, etc.):

```bash
# host: Re-create from scratch
lxc launch images:debian/12 hermes-agent -c limits.cpu=2 -c limits.memory=8GB
lxc exec hermes-agent bash

# Then follow the Deployment guide (docs/deployment.md) sections 3–6:
#   3. Hermes Agent Installation
#   4. Git and GitHub Integration
#   5. Telegram Integration
#   6. Secret Management

# After deployment:
cd /root
git clone "https://johnalencar-agent:${GITHUB_TOKEN}@github.com/jpedroalencar/agent-env-selfhosted.git"
cd agent-env-selfhosted
git config user.name "johnalencar-agent"
git config user.email "johnalencar-agent@users.noreply.github.com"
```

**What is lost and needs manual re-creation:**
- Hermes session history and conversation threads
- Agent persistent memory (`~/.hermes/memories/`)
- Persona memory files (`~/.hermes/personas/*/memory.md`)
- Any content artifacts in `~/.hermes/content/`
- Cron job state

---

## 4. Routine Maintenance

### 4.1 Weekly Checklist

- [ ] `df -h` — check disk usage (< 80% recommended)
- [ ] `hermes --version` — check for available updates
- [ ] `cd /root/agent-env-selfhosted && git status` — verify working tree is clean
- [ ] `tail -5 /root/.hermes/errors.log` — review recent errors
- [ ] Send a test message to the Telegram bot — confirm agent is responsive
- [ ] Verify LXD container is running (`lxc list` from host)
- [ ] Check latest backup evidence — verify no gaps in last 7 days

### 4.2 Monthly Checklist

- [ ] Run a full backup: `sudo /usr/local/bin/backup-container.sh` (host)
- [ ] Verify backup evidence exists inside the container
- [ ] Review and rotate GitHub token if nearing expiry
- [ ] Review Hermes logs for recurring error patterns
- [ ] Check for Hermes updates and apply if stable
- [ ] Review `.gitignore` — ensure no new file patterns need exclusion
- [ ] Clean up old manual snapshots (keep last 3):
  ```bash
  # host:
  lxc info hermes-agent | grep -A 20 '^Snapshots:'
  lxc delete hermes-agent/old-snapshot-name
  ```

### 4.3 Backup Procedure

Backups are managed by the scripted workflow on the host:

```bash
# 1. Run a full backup (host):
# host:
sudo /usr/local/bin/backup-container.sh

# 2. Verify backup evidence inside the container:
ls -t /root/agent-env-selfhosted/artifacts/operations-manager/host-validation/backup-evidence-*.md | head -1

# 3. Export secrets (must be done separately — not in the repo):
tar -czf ~/hermes-secrets-backup-$(date +%Y%m%d).tar.gz \
  -C /root/.config/hermes secrets.env

# 4. (Optional) Archive export for off-site storage (host):
# host:
lxc export hermes-agent /tmp/hermes-export-$(date +%Y%m%d).tar.gz

# 5. Transfer backup files to a secure off-site location (e.g., S3, backup VPS)
```

See `docs/backup-recovery.md` for the full backup and restore reference.

---

## 5. Troubleshooting

### 5.1 Telegram Bot Not Responding

```bash
# 1. Check gateway log
tail -30 /root/.hermes/gateway.log

# 2. Check error log
tail -10 /root/.hermes/errors.log

# 3. Test Telegram API connectivity
curl -s -o /dev/null -w "%{http_code}" "https://api.telegram.org"
# Expected: 200

# 4. Verify bot token is configured
grep -A2 'gateway:' /root/.hermes/config.yaml | grep telegram

# 5. Check Hermes process is running
ps aux | grep hermes
```

### 5.2 Agent Not Responding to Any Input

```bash
# 1. Check if Hermes process is running
ps aux | grep hermes
# PID 1 should show /usr/local/bin/hermes

# 2. Check agent log for recent activity
tail -30 /root/.hermes/agent.log

# 3. Check error log
tail -20 /root/.hermes/errors.log

# 4. Check LLM provider connectivity
source ~/.config/hermes/secrets.env
curl -s -o /dev/null -w "%{http_code}" "https://api.deepseek.com"
# Expected: 200 (or 4xx for auth errors — check API key)

# 5. If nothing works, restart the container (host):
# host:
lxc restart hermes-agent
```

### 5.3 Git Push Fails

```bash
# 1. Check authentication
source ~/.config/hermes/secrets.env
curl -s -H "Authorization: token *** "https://api.github.com/user"
# If this fails, the token is invalid or expired → Rotate (see 2.8)

# 2. Check remote connectivity
curl -s -o /dev/null -w "%{http_code}" "https://github.com"
# Expected: 200

# 3. Verify remote URL
cd /root/agent-env-selfhosted
git remote -v
# Expected: origin https://johnalencar-agent:***n
```

### 5.4 LLM Provider Rate Limited (429)

```bash
# 1. Confirm in logs
grep -i "429\|rate" /root/.hermes/errors.log

# 2. Check provider status page (DeepSeek: status.deepseek.com)

# 3. The fallback provider (OpenRouter) should auto-activate.
#    Verify by checking recent agent responses.

# 4. If both providers are down, the agent is effectively dead until
#    at least one recovers. No container-side fix — wait for provider recovery.
```

### 5.5 Container Logs Growing Too Large

```bash
# Check log sizes
du -sh /root/.hermes/*.log | sort -rh

# Truncate specific logs (safe to do while Hermes is running):
truncate -s 0 /root/.hermes/gateway.log
truncate -s 0 /root/.hermes/agent.log

# Hermes will continue writing to these files — they'll recreate as needed.
```
