# Backup — Phase Completion Report

> **Date:** 2026-06-24
> **Phases Covered:** 1 (Foundation) + 1.1 (Host Validation Evidence)
> **Status:** ✅ Complete (restore testing pending)

---

## 1. Architecture

### Current Deployment

```text
VPS Host (Ubuntu 24.04)
├── LXD 5.21.4
│   ├── hermes (running container — Debian 12)
│   │   └── /root/agent-env-selfhosted/
│   │       └── artifacts/operations-manager/host-validation/
│   │           ├── backup-evidence-20260624-005910.md  ← evidence artifact
│   │           └── ...
│   ├── backup-20260623-190808 (snapshot)
│   ├── backup-20260624-002553 (snapshot)
│   ├── backup-20260624-005910 (snapshot)
│   └── ... (up to 7 retained)
├── /usr/local/bin/backup-container.sh
├── /usr/local/bin/restore-container.sh
└── /var/log/hermes-backup.log
```

### Toolchain

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Backup | `lxc snapshot` | Atomic full-container filesystem capture (copy-on-write) |
| Retention | `backup-container.sh` | Automatic pruning of old `backup-*` snapshots |
| Restore | `lxc restore` | Full-container rollback to a specific snapshot state |
| Evidence | `lxc file push` + markdown | Machine-readable evidence injected into container's repository |
| Audit | Host-validation artifacts | Repository-visible backup confirmation without host access |

### Key Design Decisions

1. **LXD snapshots instead of file-level backup.** Full-container atomic captures eliminate coordination complexity. No need to stop the container or coordinate multiple volumes.
2. **Host-side execution.** `lxc` CLI is not available inside the container. All backup/restore operations run on the VPS host.
3. **Evidence injection bridges the trust gap.** The container cannot inspect `lxc info` output. Evidence artifacts pushed via `lxc file push` make backup status visible without operator statements.
4. **Graceful degradation.** Evidence generation, injection, and verification are supplementary. A backup that succeeds with failed evidence injection is still exit code 0.

---

## 2. Backup Workflow

### Flow

```text
User or cron invokes backup-container.sh
    │
    ├── 1. Pre-flight: verify lxc exists, container exists, no snapshot in progress
    │
    ├── 2. Create timestamped snapshot: backup-YYYYMMDD-HHMMSS
    │
    ├── 3. Verify snapshot exists via lxc info parsing
    │      ├── Found → continue
    │      └── Not found → die (exit 1)
    │
    ├── 4. Apply retention: prune backup-* snapshots beyond 7 (configurable)
    │
    ├── 5. Generate host validation evidence (Phase 1.1)
    │      ├── Write YAML-frontmattered markdown to /tmp/
    │      ├── lxc file push into container at artifacts/.../host-validation/
    │      ├── Verify via stat inside container
    │      ├── Clean up host temp file
    │      └── Any failure → log WARNING, continue (no exit code change)
    │
    └── 6. Summary: log completion, list current snapshots
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Backup successful. Evidence may or may not have been injected (non-fatal). |
| 1 | Backup failed. Pre-flight failure, snapshot creation failure, or snapshot verification failure. |

### Configurability

| Variable | Default | Description |
|----------|---------|-------------|
| `CONTAINER_NAME` | `hermes` | LXD container to back up |
| `RETENTION_COUNT` | `7` | Number of `backup-*` snapshots to retain |
| `DRY_RUN` | `false` | Preview without creating snapshots |
| `REPO_PATH_IN_CONTAINER` | `/root/agent-env-selfhosted` | Hermes repository path inside container |
| `EVIDENCE_DIR` | `artifacts/operations-manager/host-validation` | Evidence output directory (relative to repo) |
| `EVIDENCE_TMPDIR` | `/tmp/hermes-backup-evidence` | Host-side temp directory for evidence generation |

### Compatibility

- **LXD 5.21+:** The `list_snapshots()` function parses `lxc info` output using a dual-format awk parser that handles both legacy indented lists and LXD 5.21 pipe-delimited table output.
- **ARM64:** Tested on Ampere A1 (Oracle Cloud free-tier). No compatibility issues.

---

## 3. Restore Workflow

### Flow

```text
Operator invokes restore-container.sh
    │
    ├── 1. Pre-flight: verify lxc exists, container exists
    │
    ├── 2. List available backup-* snapshots
    │      ├── Interactive: prompt operator to select by number
    │      └── Direct: SNAPSHOT_NAME env var
    │
    ├── 3. Safety warning and operator confirmation
    │      └── Must type "yes" to proceed
    │
    ├── 4. Pre-restore snapshot (only if container is running)
    │      └── Named: pre-restore-YYYYMMDD-HHMMSS
    │
    ├── 5. Stop container (graceful, then --force if timeout)
    │
    ├── 6. lxc restore to selected snapshot
    │      └── Failure → start container in current state, die
    │
    ├── 7. Start container
    │
    └── 8. Verification: lxc list to confirm running state
```

### Safety Features

| Feature | Implementation |
|---------|---------------|
| Operator confirmation | Warning banner displayed. Must type "yes". Any other input aborts. |
| Pre-restore snapshot | Automatic `pre-restore-*` snapshot created if container is running |
| Graceful stop | `lxc stop --timeout 30` before `--force` |
| Restore failure recovery | Container started in current state if restore fails |
| Dry-run mode | `DRY_RUN=true` — shows actions without executing |
| Non-interactive mode | `SNAPSHOT_NAME=backup-20260623-143000` — for scripting |

### Restore Testing Status

**Not yet performed.** The restore procedure is fully documented and the script is deployed to `/usr/local/bin/restore-container.sh` on the host. Two verification paths exist:

| Option | Method | Status |
|--------|--------|--------|
| A | Full restore to current environment | ⬜ Pending — requires maintenance window |
| B | Manual validation (snapshot exists, size > 0) | ✅ Verified on first backup |

---

## 4. Evidence Workflow

### Lifecycle

```text
  Host                                Container
  ──────                              ─────────
  1. backup-container.sh runs
  2. Snapshot created ✓
  3. Retention applied ✓
  4. Generate evidence.md
     in /tmp/hermes-backup-evidence/
                                      5. lxc file push →
                                        artifacts/.../host-validation/
                                      6. Verify via stat
                                         (exists and size > 0)
  7. Clean up temp file
```

### Evidence Artifact Structure

```markdown
---
timestamp: "20260624-005910"
container_name: "hermes"
snapshot_name: "backup-20260624-005910"
backup_result: "success"
retention_actions_performed: "kept 7"
freshness_days: 90
tags: ["backup", "host-validation", "lxd-snapshot", "hermes"]
persona: "operations-manager"
summary: "Host-side LXD backup evidence for container hermes: ..."
path: "artifacts/operations-manager/host-validation/backup-evidence-20260624-005910.md"
status: "verified"
---

# Host Validation Evidence — hermes
| Field | Value |
|-------|-------|
| **Timestamp** | 20260624-005910 |
| **Container** | hermes |
| **Snapshot** | backup-20260624-005910 |
...

## Backup Execution
- Script: backup-container.sh
- Snapshot name: backup-20260624-005910
...

## Retention Actions
- Policy: Keep 7 most recent 'backup-*' snapshots
...

## Validation
- Snapshot verification: confirmed present via `lxc info` parsing
```

### Audit Methodology

Host validation artifacts are the authoritative source for backup audits. To verify backup status:

```bash
# From inside the container — find the latest evidence
ls -t artifacts/operations-manager/host-validation/backup-evidence-*.md | head -1

# Read the evidence
cat artifacts/operations-manager/host-validation/backup-evidence-$(ls -t artifacts/operations-manager/host-validation/backup-evidence-*.md | head -1 | xargs basename)

# Extract key fields
grep -E "^(timestamp|snapshot_name|backup_result):" <file>
```

A valid evidence artifact (exists, size > 0, status: verified) confirms the backup without requiring operator statements or host access.

---

## 5. Validation Performed

### Script Validation

| Test | Method | Result |
|------|--------|--------|
| Syntax | `bash -n backup-container.sh` | ✅ Pass |
| Syntax | `bash -n restore-container.sh` | ✅ Pass |
| Dry-run | `DRY_RUN=true ./backup-container.sh` | ✅ Dry-run outputs correct actions |
| Snapshot creation | Host execution | ✅ `backup-20260623-190808` created |
| Snapshot verification | `lxc info` parsing | ✅ Confirmed present |
| Retention pruning | 8 snapshots → 7 kept | ✅ Correctly prunes 1 |
| Evidence generation | Host temp file | ✅ YAML frontmatter valid |
| Evidence injection | `lxc file push` + `stat` | ✅ 1,199 bytes confirmed inside container |
| LXD 5.21 compatibility | Table-format `lxc info` parsing | ✅ Tested with simulated output |

### Parser Validation (list_snapshots)

The `list_snapshots()` function was tested against both LXD output formats:

| Format | Input | Output | Status |
|--------|-------|--------|--------|
| Legacy indented | 3 snapshots listed under `snapshots:` | `backup-20260623-190808`, `backup-20260623-150000`, `phase1-complete` | ✅ |
| LXD 5.21 table | 2 snapshots in pipe-delimited table | `phase1-complete`, `backup-20260624-002553` | ✅ |
| Empty list | No snapshots | No output, no errors | ✅ |
| Snapshot verification | Simulated `for snap in $(list_snapshots)` | `backup-20260624-002553` correctly found | ✅ |
| Retention | 8 snapshots, keep 7 | 1 correctly identified for pruning | ✅ |

### Evidence Audit

| Metric | Finding |
|--------|---------|
| Latest evidence file | `backup-evidence-20260624-005910.md` |
| Snapshot name | `backup-20260624-005910` |
| Backup result | `success` |
| File size | 1,199 bytes (> 0 — valid) |
| YAML fields | 12 fields present, all valid |
| Status | `verified` |

---

## 6. Known Limitations

| Limitation | Impact | Category |
|------------|--------|----------|
| **No restore testing performed** | Restore path is documented and scripted but never exercised end-to-end | Operational |
| **Local storage only** | VPS disk failure destroys both container and snapshots | Architecture |
| **No automated scheduling** | Cron/systemd timer documented but not configured | Operational |
| **No secrets export step** | Secrets must be backed up manually outside the backup script | Feature gap |
| **No monitoring** | Backup failures are only visible via host logs or evidence gaps | Observability |
| **No notification** | Success/failure events do not reach Telegram | Observability |
| **No git commit of evidence** | Evidence files are injected into the container filesystem but not committed to git. Container rebuild loses history. | Process gap |
| **No off-site copy** | No protection against Oracle Cloud account termination | Architecture |

### Risk Assessment

| Risk | Severity | Likelihood | Mitigation |
|------|----------|------------|------------|
| Restore script has untested code path | High | Low | All shell syntax validated. Script deployed. |
| VPS disk failure | Critical | Low | Oracle Cloud persistent block storage. |
| Evidence lost on container rebuild | Medium | Low | Cron scheduling increases backup frequency. |
| No monitoring for silent failure | Low | Medium | Evidence audit detects missing artifacts. |

---

## 7. Future Enhancements

### Phase 1.2 — Completion (High Priority)

| Enhancement | Rationale | Effort |
|------------|-----------|--------|
| Configure cron scheduling | Automate daily backups | 10 min |
| Commit evidence to git | Preserve backup history across container rebuilds | 15 min |
| Perform restore test | Validate restore script end-to-end | 30 min |

### Phase 2 — Off-Site Replication (Medium Priority)

| Enhancement | Rationale | Effort |
|------------|-----------|--------|
| rsync/S3-compatible off-site backup | Protect against VPS disk failure | Medium |
| Secrets export step in backup script | Eliminate manual secrets backup | Low |
| Separate secrets backup automation | Document and script secrets export | Low |

### Phase 2.1 — Observability (Medium Priority)

| Enhancement | Rationale | Effort |
|------------|-----------|--------|
| Telegram notification on success/failure | No more log-walking to check backup status | Medium |
| Evidence monitoring | Detect missing evidence artifacts | Low |
| Stale backup alert | Alert if no new evidence within 48 hours | Low |

### Phase 3 — Restore Drill (Ongoing)

| Enhancement | Rationale | Effort |
|------------|-----------|--------|
| Quarterly restore testing | Ensure restore path works | 30 min/quarter |
| Documented runbook with screenshots | Lower cognitive load during incident | Medium |

---

## 8. File Manifest

### Created/Modified During Backup Implementation

| File | Purpose | Phase |
|------|---------|-------|
| `scripts/backup-container.sh` | LXD snapshot backup with retention and evidence injection | 1 + 1.1 |
| `scripts/restore-container.sh` | LXD snapshot restore with safety features | 1 |
| `docs/backup-recovery.md` | Comprehensive backup/recovery documentation | 1 + 1.1 |

### Evidence Storage

| Path | Purpose |
|------|---------|
| `artifacts/operations-manager/host-validation/` | Host validation evidence artifacts |
| `artifacts/operations-manager/host-validation/.gitkeep` | Directory tracking in git |

### Related Documentation

| File | Relationship |
|------|-------------|
| `README.md` | Current status and roadmap references |
| `docs/operations.md` | Maintainer runbook references backup procedure |
| `docs/reviews/knowledge-vault-phase1-review.md` | Knowledge Vault phase review (parallel capability) |

---

## 9. Architecture Diagram

```text
                         ┌─────────────────────────────┐
                         │         VPS Host             │
                         │  ┌───────────────────────┐   │
                         │  │  backup-container.sh   │   │
                         │  │  restore-container.sh  │   │
                         │  │  /var/log/hermes-*.log │   │
                         │  └───────────────────────┘   │
                         │                              │
                         │  ┌──────────┐   ┌─────────┐  │
                         │  │  LXD     │   │  LXD    │  │
                         │  │  Snapshot ├───┤ Restore │  │
                         │  └────┬─────┘   └─────────┘  │
                         │       │                       │
                         │  ┌────▼───────────────────┐   │
                         │  │   Hermes Container      │   │
                         │  │   (Debian 12)           │   │
                         │  │                        │   │
                         │  │  ┌──────────────────┐  │   │
                         │  │  │ Repository        │  │   │
                         │  │  │  artifacts/       │  │   │
                         │  │  │  .../host-validation│  │ │
                         │  │  │  evidence-*.md    │  │   │
                         │  │  └──────────────────┘  │   │
                         │  │                        │   │
                         │  │  lxc file push ◄─────────┘  │
                         │  └────────────────────────┘   │
                         └─────────────────────────────┘
                                    │
                         ┌──────────▼──────────┐
                         │   Host Evidence     │
                         │   /tmp/hermes-      │
                         │   backup-evidence/   │
                         │   (cleaned up after) │
                         └─────────────────────┘
```

---

## 10. Recommendations

1. **Schedule and perform a restore test** as the next operational action. This is the single remaining gap for full Phase 1 verification.
2. **Commit evidence artifacts to git** as part of the backup workflow, or configure a cron job inside the container to periodically add and push new evidence files.
3. **Configure cron scheduling** for daily automated backups. The systemd timer template in `docs/backup-recovery.md §4.7` is ready to deploy.
4. **Add secrets export** to the backup script to eliminate the manual step documented in `docs/operations.md §4.3`.
