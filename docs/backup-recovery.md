# Backup & Recovery

Phase 1 implementation of automated LXD snapshots for the Hermes container.

**Target audience:** A future maintainer with no prior knowledge of the platform. Every procedure is documented with exact commands.

---

## 1. Backup Architecture

### Current Design

```text
VPS Host
├── LXD
│   ├── hermes (running container)
│   ├── backup-20260623-143000 (snapshot)
│   ├── backup-20260623-150000 (snapshot)
│   └── ... (up to 7 retained)
└── /var/log/hermes-backup.log
```

- **Tool:** Native LXD snapshots — no additional software required
- **Scope:** Full container filesystem (Hermes, config, skills, content, session DB)
- **Storage:** Local to the VPS host (same disk as the container)
- **Exclusions:** Nothing — LXD snapshots capture the entire container state atomically
- **Secrets:** Not included in the snapshot scope — secrets are stored in `~/.config/hermes/secrets.env` on the container filesystem, which IS captured by the snapshot. However, secrets should be backed up separately (see §8 — Recovery Limitations)

### What Gets Backed Up

| Component | Captured by Snapshot? | Notes |
|-----------|----------------------|-------|
| Hermes Agent binary | ✅ | Full container filesystem |
| Hermes config.yaml | ✅ | Full container filesystem |
| Agent memory (MEMORY.md, USER.md) | ✅ | Full container filesystem |
| Persona memories | ✅ | Full container filesystem |
| Persona workspaces | ✅ | Full container filesystem |
| Session database | ✅ | Full container filesystem |
| Content artifacts | ✅ | Full container filesystem |
| Cron job state | ✅ | Full container filesystem |
| Git repository clone | ✅ | Full container filesystem |
| Installed packages | ✅ | Full container filesystem |
| Secrets (secrets.env) | ✅ | On container filesystem |

### What Is NOT Backed Up (by snapshot alone)

| Component | How to Back Up | Current Status |
|-----------|---------------|----------------|
| GitHub PAT | Export `~/.config/hermes/secrets.env` separately | ⬜ Documented but not automated |
| LXD host configuration | Not covered by Phase 1 | ⬜ Planned |
| Off-site copy | Not covered by Phase 1 | ⬜ Planned |

---

## 2. Snapshot Naming Convention

Format:

```
backup-YYYYMMDD-HHMMSS
```

| Component | Description | Example |
|-----------|-------------|---------|
| `backup-` | Prefix identifying script-created snapshots | `backup-` |
| `YYYYMMDD` | Date in ISO format | `20260623` |
| `-` | Separator | `-` |
| `HHMMSS` | Time in 24-hour format | `143000` |

Example: `backup-20260623-143000`

Other snapshot names (not created by the backup script):

```
pre-restore-20260623-150000   # Auto-created by restore-container.sh before restore
manual-20260623-160000        # Manually created snapshots
```

---

## 3. Retention Policy

| Setting | Value | Rationale |
|---------|-------|-----------|
| Retained snapshots | 7 most recent | Balances recovery window (7 days of daily backups) with disk usage |
| Pruning method | Automatic on each backup run | Snapshots beyond the 7 most recent are deleted |
| Identification | Snapshots with `backup-` prefix | Other snapshots (pre-restore, manual) are never pruned |
| Configurability | `RETENTION_COUNT` env var | Override: `RETENTION_COUNT=14 ./backup-container.sh` |

### Disk Space Considerations

LXD snapshots share blocks with the container (copy-on-write). The actual disk usage per snapshot is typically small (tens to hundreds of MB) unless the container filesystem changes significantly between snapshots.

To check actual snapshot disk usage:

```bash
# From the host
lxc info hermes
# Look for snapshots section with size info
```

If disk space is a concern, reduce retention: `RETENTION_COUNT=3 ./backup-container.sh`

---

## 4. Backup Procedure

### 4.1 Prerequisites

- SSH access to the VPS host
- LXD installed and initialized on the host
- The Hermes container (`hermes`) must exist

### 4.2 One-Time Setup

Copy the scripts from the repository to the host:

```bash
# From the host
# The scripts live in the repository at scripts/backup-container.sh
# Transfer via SCP from your local machine:
scp -P <ssh-port> scripts/backup-container.sh <user>@<host-ip>:/usr/local/bin/
scp -P <ssh-port> scripts/restore-container.sh <user>@<host-ip>:/usr/local/bin/
```

Or clone the repository on the host:

```bash
# From the host
cd /opt
git clone "https://johnalencar-agent:${GITHUB_TOKEN}@github.com/jpedroalencar/agent-env-selfhosted.git"
```

### 4.3 Run a Backup

```bash
# From the host
sudo ./backup-container.sh
```

Expected output:

```
[2026-06-23 14:30:00] === Backup started for container: hermes ===
[2026-06-23 14:30:01] Creating snapshot 'backup-20260623-143000' for container 'hermes'...
[2026-06-23 14:30:02] Snapshot 'backup-20260623-143000' created successfully.
[2026-06-23 14:30:02] Verified: snapshot 'backup-20260623-143000' is present.
[2026-06-23 14:30:02] Applying retention policy: keeping 7 most recent 'backup-*' snapshots.
[2026-06-23 14:30:02] Retention applied. Kept 7 of 8 total 'backup-*' snapshots.
[2026-06-23 14:30:02] === Backup completed for container: hermes ===
```

### 4.4 Dry Run

Preview what the script would do without making changes:

```bash
DRY_RUN=true ./backup-container.sh
```

### 4.5 Custom Container Name

```bash
CONTAINER_NAME=my-other-container ./backup-container.sh
```

### 4.6 Custom Retention Count

```bash
RETENTION_COUNT=14 ./backup-container.sh
```

### 4.7 Automating with Cron

To run a backup daily at midnight:

```bash
sudo crontab -e
# Add:
0 0 * * * /usr/local/bin/backup-container.sh >> /var/log/hermes-backup-cron.log 2>&1
```

Or use a systemd timer:

```ini
# /etc/systemd/system/hermes-backup.service
[Unit]
Description=Hermes LXD backup snapshot

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup-container.sh

[Install]
WantedBy=multi-user.target
```

```ini
# /etc/systemd/system/hermes-backup.timer
[Unit]
Description=Daily Hermes backup

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now hermes-backup.timer
```

---

## 5. Restore Procedure

### 5.1 Interactive Restore

```bash
# From the host
sudo ./restore-container.sh
```

This will:
1. Display all available `backup-` snapshots
2. Prompt you to select one by number
3. Show a safety warning and require confirmation
4. Stop the container (if running)
5. Create a pre-restore snapshot (so you can undo)
6. Restore the selected snapshot
7. Start the container

### 5.2 Non-Interactive Restore

Specify the snapshot name directly (useful for scripting):

```bash
sudo SNAPSHOT_NAME=backup-20260623-143000 ./restore-container.sh
```

### 5.3 Dry Run

```bash
DRY_RUN=true ./restore-container.sh
```

---

## 6. Validation Procedure

A backup is not considered verified solely because a snapshot was created. Verification requires one of:

### Option A: Restore to Current Environment

```bash
# 1. Create a test snapshot
sudo ./backup-container.sh

# 2. Verify the snapshot name
sudo lxc info hermes | grep -A 20 '^Snapshots:'

# 3. Stop the container and restore (see restore procedure §5)
sudo ./restore-container.sh
```

### Option B: Manual Validation

If full restoration is disruptive, validate by confirming snapshot integrity:

```bash
# 1. Create a backup
sudo ./backup-container.sh

# 2. Verify the snapshot exists and has content
sudo lxc info hermes | grep -A 20 '^Snapshots:'
# Expected: backup-YYYYMMDD-HHMMSS in the "Snapshots:" section

# 3. Check snapshot info
sudo lxc info hermes
# Look for "Snapshots:" section with size > 0

# 4. Verify container is still running normally after backup
sudo lxc list hermes
# Expected: RUNNING

# 5. Verify Hermes is responding by sending a test message via Telegram
```

**Phase 1 validation status:** Manual validation (Option B) only. Full restore testing (Option A) requires operator confirmation and a scheduled maintenance window.

---

## 7. Failure Scenarios

### Scenario 1: Snapshot Creation Fails

**Symptom:** Script exits with `FATAL: Snapshot creation failed`

**Causes and fixes:**
- **Disk full:** Check host disk space with `df -h`. Free space by removing old snapshots: `lxc delete hermes/old-snapshot-name`
- **Container busy:** Wait for any running operations to complete, then retry
- **LXD not running:** Check with `lxd --version` or `snap services lxd`

### Scenario 2: Container Not Found

**Symptom:** Script exits with `FATAL: Container 'hermes' does not exist`

**Fix:** Verify the correct container name:
```bash
lxc list
```
If the container has a different name, set `CONTAINER_NAME`:
```bash
CONTAINER_NAME=correct-name ./backup-container.sh
```

### Scenario 3: Restore Fails

**Symptom:** Script exits with `FATAL: Restore failed`

**Causes and fixes:**
- **Container still running:** The script attempts to stop the container first. If it fails, try: `lxc stop hermes --force`
- **Snapshot corrupted:** Rare with LXD. Try restoring a different snapshot.
- **LXD version mismatch:** Very rare. Check `lxd --version` and verify it's consistent.

### Scenario 4: Container Won't Start After Restore

**Symptom:** Container stops or fails to start after restore

**Recovery:**
```bash
# 1. Check container status
lxc info hermes

# 2. Check logs
lxc info hermes --show-log

# 3. Roll back to the pre-restore snapshot (if one was created)
lxc snapshot hermes pre-restore-YYYYMMDD-HHMMSS
lxc restore hermes pre-restore-YYYYMMDD-HHMMSS
lxc start hermes

# 4. If Hermes itself fails to start (but container is running):
lxc exec hermes -- hermes --version
# If Hermes is broken, restore from a different snapshot
```

### Scenario 5: All Snapshots Lost

**Symptom:** `lxc info hermes | grep -A 20 '^Snapshots:'` shows no snapshots

**Impact:** Total container loss requires complete rebuild from the GitHub repository + secrets backup.

**Recovery:** Follow `docs/deployment.md` from scratch. After deployment:
```bash
cd /root
git clone "https://johnalencar-agent:${GITHUB_TOKEN}@github.com/jpedroalencar/agent-env-selfhosted.git"
```

**What is irretrievably lost:** Session history, agent memory, persona memory, content artifacts, cron job state.

---

## 8. Recovery Limitations

### Phase 1 Known Gaps

| Limitation | Impact | Mitigation | Planned Resolution |
|-----------|--------|------------|-------------------|
| Local storage only | If the VPS disk fails, snapshots are lost | Not mitigated in Phase 1 | Phase 2: off-site replication |
| No automatic scheduling | Backups require manual invocation or cron setup | Cron setup is documented (§4.7) but not configured | Phase 1.1: cron job setup |
| No separate secrets backup | Secrets file restored with container, but no independent copy | Manual secrets export is documented in operations.md §4.3 | Phase 1.1: add secrets export to backup script |
| No restore testing | Option B (manual validation) only — no verified restore has been performed | Documented validation procedures (§6) require operator action | ☐ Operator: must perform Option A or confirm Option B |
| No monitoring | No alert if backup fails or retention fails | Logs must be checked manually | Phase 2: monitoring integration |
| No notification | No Telegram alert on backup success/failure | Not mitigated | Phase 2: notification hook |

### What This Backup Does NOT Protect Against

- **VPS disk failure:** Snapshots are on the same disk as the container. A disk failure destroys both.
- **Oracle Cloud account termination:** If the OCI account is terminated, both the container and its snapshots are lost.
- **Accidental snapshot deletion:** If someone runs `lxc delete hermes/backup-*`, all backups are gone.
- **Credentials expiry:** If the GitHub PAT expires, the repository becomes inaccessible even if the backup is intact.
- **Data corruption that propagates to snapshots:** If a bug corrupts the container filesystem, the next snapshot also captures the corruption.

---

## 9. Operator Action Required

### Active Requirements

The following must be completed by the operator (John) before Phase 1 can be considered operational:

1. **Run the backup script** to create the first snapshot:
   ```
   # From the host:
   sudo /path/to/scripts/backup-container.sh
   ```

2. **Verify the snapshot exists:**
   ```
   sudo lxc info hermes | grep -A 20 '^Snapshots:'
   ```

3. **Confirm completion** so this documentation can be updated with real results and committed.

### Future Phases

| Phase | Scope | Status |
|-------|-------|--------|
| 1 | Local LXD snapshots, retention, restore script | 🟡 Awaiting operator action |
| 1.1 | Cron scheduling, secrets export in backup script | ⬜ Planned |
| 2 | Off-site replication (rsync/S3-compatible) | ⬜ Planned |
| 2.1 | Telegram notification on backup success/failure | ⬜ Planned |
| 3 | Restore testing — scheduled quarterly restore drill | ⬜ Planned |
