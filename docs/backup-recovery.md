# Backup & Recovery

> **Phases covered:** 1 (Foundation) + 1.1 (Host Validation Evidence)
> **Status:** ✅ Implementation complete. Restore testing pending.
> **Completion report:** [docs/reviews/backup-phase-completion.md](reviews/backup-phase-completion.md)
>
> **Target audience:** A future maintainer with no prior knowledge of the platform. Every procedure is documented with exact commands.

---

## 1. Backup Architecture

### Current Design

```text
VPS Host
├── LXD
│   ├── hermes-agent (running container)
│   │   └── artifacts/operations-manager/host-validation/
│   │       └── backup-evidence-YYYYMMDD-HHMMSS.md  ← injected via lxc file push
│   ├── backup-20260623-143000 (snapshot)
│   ├── backup-20260623-150000 (snapshot)
│   └── ... (up to 7 retained)
├── /usr/local/bin/backup-container.sh
├── /usr/local/bin/restore-container.sh
├── /var/log/hermes-backup.log
└── /tmp/hermes-backup-evidence/  ← temp workspace (cleaned up after push)
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
[2026-06-23 14:30:00] === Backup started for container: hermes-agent ===
[2026-06-23 14:30:01] Creating snapshot 'backup-20260623-143000' for container 'hermes-agent'...
[2026-06-23 14:30:02] Snapshot 'backup-20260623-143000' created successfully.
[2026-06-23 14:30:02] Verified: snapshot 'backup-20260623-143000' is present.
[2026-06-23 14:30:02] Applying retention policy: keeping 7 most recent 'backup-*' snapshots.
[2026-06-23 14:30:02] Retention applied. Kept 7 of 8 total 'backup-*' snapshots.
[2026-06-23 14:30:02] === Backup completed for container: hermes-agent ===
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

## 6A. Host Validation Evidence

### 6A.1 Overview

Starting in Phase 1.1, every successful host-side backup automatically generates a **machine-readable evidence artifact** and injects it into the Hermes container's repository. This allows Hermes to independently verify backup execution without operator confirmation.

### 6A.2 Evidence Lifecycle

```text
1. Snapshots created ✓
2. Retention applied ✓
3. Evidence artifact generated (host)
4. Evidence pushed via lxc file push (host → container)
5. Evidence verified inside container (stat checks)
6. Host temp file cleaned up
7. Artifact accessible at artifacts/operations-manager/host-validation/
```

### 6A.3 Storage Location

```
<repo-root>/artifacts/operations-manager/host-validation/
├── backup-evidence-YYYYMMDD-HHMMSS.md   ← Evidence artifact
├── backup-evidence-YYYYMMDD-HHMMSS.md
└── ...
```

The directory is automatically created by the backup script if it does not exist.

### 6A.4 YAML Metadata Schema

Every evidence artifact contains the following frontmatter:

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | string | Snapshot creation time (`YYYYMMDD-HHMMSS`) |
| `container_name` | string | LXD container backed up |
| `snapshot_name` | string | Name of the created snapshot |
| `backup_result` | string | Always `"success"` (script exits before evidence on failure) |
| `retention_actions_performed` | string | Summary of retention policy applied |
| `freshness_days` | int | Always `90` — evidence is stable host-side data |
| `tags` | list | Standard Knowledge Vault tags |
| `persona` | string | Always `"operations-manager"` |
| `summary` | string | One-line description of evidence content |
| `path` | string | Relative path within the repo |
| `status` | string | Always `"verified"` |

### 6A.5 Evidence Content

Each artifact contains:

- **Backup execution** — timestamp, container name, snapshot name
- **Retention actions** — how many snapshots were kept, pruned
- **Validation** — snapshot verification results, evidence injection status

### 6A.6 Evidence Verification Process

1. **Generation:** Script writes evidence to `/tmp/hermes-backup-evidence/` on the host
2. **Push:** Script uses `lxc file push` to inject into the container at the configured repo path
3. **Verify:** Script runs `lxc exec <container> -- stat -c "%s" <path>` to confirm:
   - File exists inside the container
   - File size is greater than zero bytes
4. **Log:** Result is logged to `/var/log/hermes-backup.log` as either:
   - `"Evidence successfully injected into container (N bytes)."`
   - `"WARNING: Evidence injection could not be verified. Backup was successful."`
5. **Cleanup:** Host temp file is removed regardless of verification outcome

### 6A.7 Graceful Degradation

Evidence generation, injection, and verification **never invalidate a successful backup**. All failures follow this pattern:

```
WARNING: <description of failure>. Backup was successful.
```

The script continues past any evidence failure without changing the exit code. A backup that succeeds with failed evidence injection is still exit code 0.

### 6A.8 Audit Methodology

Host validation artifacts are **authoritative evidence** for host-side backup operations. Future audits must:

- Use host-validation artifacts as primary evidence
- Not classify backups as missing solely because the container cannot directly inspect host resources (e.g., `lxc info`, `lxc list-snapshots`)
- Distinguish between:
  - **Missing evidence:** No artifact exists for a given period — backup may not have run
  - **Failed backup:** Script exited non-zero — logged on host
  - **Unavailable host visibility:** No host tools available from inside container — not a backup failure

**Detection without operator confirmation:** If a valid evidence artifact exists at `artifacts/operations-manager/host-validation/backup-evidence-*.md`, the backup is considered confirmed. No operator statement is required.

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

## 9. Operational Status

### Completed Actions

The following have been completed by the operator (John):

1. ✅ **Scripts transferred to host:** `backup-container.sh` and `restore-container.sh` deployed to `/usr/local/bin/`
2. ✅ **First backup executed:** Snapshot `backup-20260623-190808` created and verified
3. ✅ **Host validation evidence:** Automated evidence injection operational (Phase 1.1)

### Remaining Actions

1. **Restore testing:** Run `restore-container.sh` against a backup snapshot in a maintenance window
2. **Cron scheduling:** Configure `hermes-backup.timer` to automate daily backups

### Known Gaps

| Limitation | Impact | Mitigation | Planned Resolution |
|-----------|--------|------------|-------------------|
| Local storage only | If the VPS disk fails, snapshots are lost | Not mitigated in Phase 1.1 | Phase 2: off-site replication |
| No restore testing | Option B (manual validation) only | Evidence artifacts enable independent confirmation | Quarterly restore drill (Phase 3) |
| No monitoring | No alert if backup fails | Logs must be checked manually | Phase 2: monitoring integration |
| No notification | No Telegram alert on backup success/failure | Evidence artifacts are repository-visible | Phase 2.1: notification hook |

### Future Phases

| Phase | Scope | Status |
|-------|-------|--------|
| 1 | Local LXD snapshots, retention, restore script | ✅ Complete |
| 1.1 | Host validation evidence, cron scheduling setup, secrets export | ✅ Evidence injection complete. Cron scheduling pending. |
| 2 | Off-site replication (rsync/S3-compatible) | ⬜ Planned |
| 2.1 | Telegram notification on backup success/failure | ⬜ Planned |
| 3 | Restore testing — scheduled quarterly restore drill | ⬜ Planned |
