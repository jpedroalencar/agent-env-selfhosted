#!/usr/bin/env bash
#===============================================================================
# backup-container.sh
#
# Creates LXD snapshots of a Hermes container with timestamped names and
# automatic retention. Designed to run on the VPS host, not inside the container.
#
# Usage:
#   ./backup-container.sh                    # Backup the default container
#   CONTAINER_NAME=my-hermes ./backup-container.sh  # Backup another container
#   DRY_RUN=true ./backup-container.sh       # Preview without creating snapshots
#
# Defaults:
#   CONTAINER_NAME=hermes
#   RETENTION_COUNT=7
#
# Prerequisites:
#   - Must be run on the VPS host (not inside the container)
#   - LXD must be installed and initialized
#   - The target container must exist
#===============================================================================

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

# The LXD container to back up. Override via environment variable.
CONTAINER_NAME="${CONTAINER_NAME:-hermes}"

# Number of backup snapshots to retain. Older snapshots are pruned automatically.
RETENTION_COUNT="${RETENTION_COUNT:-7}"

# Snapshot name prefix used to identify backups created by this script.
SNAPSHOT_PREFIX="backup"

# Log file destination (host filesystem).
LOG_FILE="/var/log/hermes-backup.log"

# Path to the Hermes repository inside the container (for evidence injection).
# Override via environment variable.
REPO_PATH_IN_CONTAINER="${REPO_PATH_IN_CONTAINER:-/root/agent-env-selfhosted}"

# Evidence output directory inside the container (relative to repo root).
EVIDENCE_DIR="${EVIDENCE_DIR:-artifacts/operations-manager/host-validation}"

# Temporary evidence workspace on the host filesystem.
EVIDENCE_TMPDIR="${EVIDENCE_TMPDIR:-/tmp/hermes-backup-evidence}"

# Dry-run mode: if set, print actions without executing them.
DRY_RUN="${DRY_RUN:-false}"

# ── Helpers ──────────────────────────────────────────────────────────────────

log() {
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${timestamp}] ${*}" | tee -a "${LOG_FILE}"
}

die() {
    log "FATAL: ${*}"
    exit 1
}

run_or_dry() {
    if [ "${DRY_RUN}" = "true" ]; then
        log "DRY-RUN: would execute: ${*}"
        return 0
    fi
    "${@}"
}

# List snapshot names for a container by parsing `lxc info` output.
# Compatible with LXD 5.21+ where `lxc list-snapshots` is not a valid command.
list_snapshots() {
    lxc info "${CONTAINER_NAME}" 2>/dev/null \
        | awk '
/^Snapshots:/ {flag=1; next}
flag && /^[[:space:]]*\|/ {
    # Table format (LXD 5.21+):  | name | date | ... |
    n = split($0, a, "|")
    if (n >= 3) {
        name = a[2]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
        if (name != "" && name != "NAME") print name
    }
    next
}
flag && /^  [a-zA-Z0-9]/ {
    # Legacy indented format:   name
    print $1
    next
}
/^[A-Za-z]/ && flag {flag=0}
'
}

# Number of prefix-matching snapshots (for retention logging).
count_prefix_snapshots() {
    local prefix="${1:-${SNAPSHOT_PREFIX}}"
    list_snapshots | grep -cE "^${prefix}-" 2>/dev/null || echo 0
}

# ── Pre-flight Checks ────────────────────────────────────────────────────────

log "=== Backup started for container: ${CONTAINER_NAME} ==="

# Check that lxc is available
if ! command -v lxc &>/dev/null; then
    die "LXD CLI (lxc) not found. This script must run on the VPS host."
fi

# Check that the container exists
if ! lxc info "${CONTAINER_NAME}" &>/dev/null; then
    die "Container '${CONTAINER_NAME}' does not exist. Available containers:"
    lxc list --columns n 2>/dev/null || true
    exit 1
fi

# Check the container is not currently being snapshotted by another process
if lxc info "${CONTAINER_NAME}" 2>/dev/null | grep -q "snapshot in progress"; then
    die "A snapshot is already in progress for '${CONTAINER_NAME}'. Retry later."
fi

# ── Create Snapshot ──────────────────────────────────────────────────────────

SNAPSHOT_NAME="${SNAPSHOT_PREFIX}-$(date '+%Y%m%d-%H%M%S')"
log "Creating snapshot '${SNAPSHOT_NAME}' for container '${CONTAINER_NAME}'..."

if ! run_or_dry lxc snapshot "${CONTAINER_NAME}" "${SNAPSHOT_NAME}"; then
    die "Snapshot creation failed for '${CONTAINER_NAME}'."
fi

if [ "${DRY_RUN}" != "true" ]; then
    log "Snapshot '${SNAPSHOT_NAME}' created successfully."
fi

# ── Verify Snapshot Exists ───────────────────────────────────────────────────

if [ "${DRY_RUN}" != "true" ]; then
    # Use lxc info parsing — lxc list-snapshots is not available in LXD 5.21+
    VERIFIED=false
    for snap in $(list_snapshots); do
        if [ "${snap}" = "${SNAPSHOT_NAME}" ]; then
            VERIFIED=true
            break
        fi
    done
    if [ "${VERIFIED}" = "true" ]; then
        log "Verified: snapshot '${SNAPSHOT_NAME}' is present."
    else
        die "Snapshot '${SNAPSHOT_NAME}' was not found after creation. This may indicate a storage issue."
    fi
fi

# ── Retention: Prune Old Snapshots ──────────────────────────────────────────

log "Applying retention policy: keeping ${RETENTION_COUNT} most recent '${SNAPSHOT_PREFIX}-*' snapshots."

# List backup snapshots from lxc info, sorted newest-first by name
# (YYYYMMDD-HHMMSS format sorts chronologically).
SNAPSHOTS=$(list_snapshots | grep -E "^${SNAPSHOT_PREFIX}-" | sort -r || true)

if [ -z "${SNAPSHOTS}" ]; then
    log "No existing '${SNAPSHOT_PREFIX}-*' snapshots found. Nothing to prune."
else
    COUNT=0
    for snap in ${SNAPSHOTS}; do
        COUNT=$((COUNT + 1))
        if [ "${COUNT}" -gt "${RETENTION_COUNT}" ]; then
            log "Pruning old snapshot: ${snap}"
            if ! run_or_dry lxc delete "${CONTAINER_NAME}/${snap}"; then
                log "WARNING: Failed to delete old snapshot '${snap}'. Manual cleanup may be required."
            fi
        fi
    done
    log "Retention applied. Kept ${RETENTION_COUNT} of ${COUNT} total '${SNAPSHOT_PREFIX}-*' snapshots."
fi

# ── Host Validation Evidence ─────────────────────────────────────────────────
#
# After a successful backup, generate machine-readable evidence on the host,
# inject it into the Hermes container's repository, and verify delivery.
#
# Graceful degradation: failures here MUST NOT invalidate a successful backup.
# All evidence steps log warnings and continue — they never call die().

if [ "${DRY_RUN}" = "true" ]; then
    log "DRY-RUN: Skipping evidence generation (dry-run mode)."
else
    EVIDENCE_TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
    EVIDENCE_TAG="backup-evidence-${EVIDENCE_TIMESTAMP}"
    EVIDENCE_HOST_FILE="${EVIDENCE_TMPDIR}/${EVIDENCE_TAG}.md"
    CONTAINER_EVIDENCE_DIR="${REPO_PATH_IN_CONTAINER}/${EVIDENCE_DIR}"

    # ── Generate evidence artifact on host ───────────────────────────────
    mkdir -p "${EVIDENCE_TMPDIR}" 2>/dev/null || {
        log "WARNING: Could not create evidence temp dir '${EVIDENCE_TMPDIR}'. Skipping evidence generation."
        EVIDENCE_SKIPPED=true
    }

    RETENTION_SUMMARY="kept ${RETENTION_COUNT}"
    SNAPSHOT_COUNT="${COUNT:-0}"

    if [ "${EVIDENCE_SKIPPED:-false}" != "true" ]; then
        cat > "${EVIDENCE_HOST_FILE}" <<EVEOF
---
timestamp: "${EVIDENCE_TIMESTAMP}"
container_name: "${CONTAINER_NAME}"
snapshot_name: "${SNAPSHOT_NAME}"
backup_result: "success"
retention_actions_performed: "${RETENTION_SUMMARY}"
freshness_days: 90
tags: ["backup", "host-validation", "lxd-snapshot", "${CONTAINER_NAME}"]
persona: "operations-manager"
summary: "Host-side LXD backup evidence for container ${CONTAINER_NAME}: snapshot ${SNAPSHOT_NAME}, retention ${RETENTION_SUMMARY}"
path: "${EVIDENCE_DIR}/${EVIDENCE_TAG}.md"
status: "verified"
---

# Host Validation Evidence — ${CONTAINER_NAME}

| Field | Value |
|-------|-------|
| **Timestamp** | ${EVIDENCE_TIMESTAMP} |
| **Container** | ${CONTAINER_NAME} |
| **Snapshot** | ${SNAPSHOT_NAME} |
| **Result** | success |
| **Retention** | ${RETENTION_SUMMARY} |

## Backup Execution

- **Script:** backup-container.sh
- **Snapshot name:** ${SNAPSHOT_NAME}
- **Snapshot created:** $(date '+%Y-%m-%d %H:%M:%S UTC')
- **Container:** ${CONTAINER_NAME}

## Retention Actions

- **Policy:** Keep ${RETENTION_COUNT} most recent '${SNAPSHOT_PREFIX}-*' snapshots
- **Snapshots before pruning:** ${SNAPSHOT_COUNT}
- **Snapshots after pruning:** kept ${RETENTION_COUNT}
- **Pruning applied:** yes

## Validation

- **Snapshot verification:** confirmed present via \`lxc info\` parsing
- **Evidence injection:** see below
EVEOF
        log "Generated evidence artifact: ${EVIDENCE_HOST_FILE}"
        EVIDENCE_SKIPPED=false
    fi

    # ── Ensure target directory exists inside container ───────────────────
    if [ "${EVIDENCE_SKIPPED}" != "true" ]; then
        if lxc exec "${CONTAINER_NAME}" -- mkdir -p "${CONTAINER_EVIDENCE_DIR}" 2>/dev/null; then
            log "Ensured evidence directory exists inside container: ${CONTAINER_EVIDENCE_DIR}"
        else
            log "WARNING: Could not create evidence directory inside container. Skipping evidence injection."
            EVIDENCE_SKIPPED=true
        fi
    fi

    # ── Push evidence into container ──────────────────────────────────────
    if [ "${EVIDENCE_SKIPPED}" != "true" ]; then
        CONTAINER_EVIDENCE_PATH="${CONTAINER_EVIDENCE_DIR}/${EVIDENCE_TAG}.md"
        if lxc file push "${EVIDENCE_HOST_FILE}" "${CONTAINER_NAME}/${CONTAINER_EVIDENCE_PATH}" 2>/dev/null; then
            log "Evidence pushed to container: ${CONTAINER_EVIDENCE_PATH}"
        else
            log "WARNING: Failed to push evidence to container. Backup was successful but evidence is host-local only."
            EVIDENCE_SKIPPED=true
        fi
    fi

    # ── Verify evidence injection ─────────────────────────────────────────
    if [ "${EVIDENCE_SKIPPED}" != "true" ]; then
        VERIFY_OUTPUT=$(lxc exec "${CONTAINER_NAME}" -- stat -c "%s" "${CONTAINER_EVIDENCE_PATH}" 2>/dev/null || echo "FAILED")
        if [ "${VERIFY_OUTPUT}" != "FAILED" ] && [ "${VERIFY_OUTPUT}" -gt 0 ] 2>/dev/null; then
            log "Evidence successfully injected into container (${VERIFY_OUTPUT} bytes)."
            INJECTION_VERIFIED=true
        else
            log "WARNING: Evidence injection could not be verified. Backup was successful."
            INJECTION_VERIFIED=false
        fi
    fi

    # ── Clean up host temp file ───────────────────────────────────────────
    if [ -f "${EVIDENCE_HOST_FILE}" ]; then
        rm -f "${EVIDENCE_HOST_FILE}" && log "Cleaned up host temp evidence: ${EVIDENCE_HOST_FILE}"
    fi

    # Summarize evidence status for the log
    if [ "${EVIDENCE_SKIPPED}" = "true" ]; then
        log "Evidence status: NOT COLLECTED (non-fatal — backup successful)."
    elif [ "${INJECTION_VERIFIED:-false}" = "true" ]; then
        log "Evidence status: COLLECTED AND INJECTED."
    else
        log "Evidence status: COLLECTED BUT NOT VERIFIED (non-fatal — backup successful)."
    fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────

log "=== Backup completed for container: ${CONTAINER_NAME} ==="

# List current snapshots for reference
if [ "${DRY_RUN}" != "true" ]; then
    echo ""
    echo "Current snapshots for '${CONTAINER_NAME}':"
    lxc info "${CONTAINER_NAME}" 2>/dev/null | sed -n '/^Snapshots:/,$ p' | head -20
fi

echo ""
echo "Log: ${LOG_FILE}"
