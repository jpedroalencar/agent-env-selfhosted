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
        | awk '/^Snapshots:/ {flag=1; next} /^[A-Za-z]/ && flag {flag=0} flag && /^  / {print $1}'
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
