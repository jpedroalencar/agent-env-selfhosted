#!/usr/bin/env bash
#===============================================================================
# restore-container.sh
#
# Restores an LXD container from a timestamped backup snapshot. Designed to run
# on the VPS host, not inside the container.
#
# Usage:
#   ./restore-container.sh                            # Interactive: list + select
#   SNAPSHOT_NAME=backup-20260623-143000 ./restore-container.sh  # Direct restore
#   DRY_RUN=true ./restore-container.sh               # Preview without restoring
#
# Defaults:
#   CONTAINER_NAME=hermes
#
# Prerequisites:
#   - Must be run on the VPS host (not inside the container)
#   - LXD must be installed and initialized
#   - The target container must exist
#   - At least one backup snapshot must exist
#
# Safety:
#   - The container will be stopped before restoration
#   - Operator confirmation is required before any destructive action
#   - A pre-restore snapshot is taken automatically if the container is running
#===============================================================================

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

# The LXD container to restore. Override via environment variable.
CONTAINER_NAME="${CONTAINER_NAME:-hermes-agent}"

# Optional: specify a snapshot name directly. If empty, interactive mode is used.
SNAPSHOT_NAME="${SNAPSHOT_NAME:-}"

# Snapshot name prefix used by backup-container.sh (for filtering).
SNAPSHOT_PREFIX="backup"

# Log file destination (host filesystem).
LOG_FILE="/var/log/hermes-restore.log"

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

prompt_yes_no() {
    local prompt="${1}"
    local response
    echo ""
    echo "⚠  ${prompt}"
    echo "   Type 'yes' to continue, anything else to abort."
    read -r response
    if [ "${response}" != "yes" ]; then
        log "ABORTED by operator."
        exit 0
    fi
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

# ── Pre-flight Checks ────────────────────────────────────────────────────────

log "=== Restore started for container: ${CONTAINER_NAME} ==="

if ! command -v lxc &>/dev/null; then
    die "LXD CLI (lxc) not found. This script must run on the VPS host."
fi

if ! lxc info "${CONTAINER_NAME}" &>/dev/null; then
    die "Container '${CONTAINER_NAME}' does not exist."
fi

# ── List Available Snapshots ─────────────────────────────────────────────────

log "Fetching available snapshots for '${CONTAINER_NAME}'..."

SNAPSHOTS=$(list_snapshots | grep -E "^${SNAPSHOT_PREFIX}-" | sort -r || true)

if [ -z "${SNAPSHOTS}" ]; then
    die "No '${SNAPSHOT_PREFIX}-*' snapshots found for container '${CONTAINER_NAME}'."
fi

echo ""
echo "Available backup snapshots for '${CONTAINER_NAME}':"
SNAPSHOT_LIST=()
INDEX=1
while IFS= read -r snap; do
    SNAPSHOT_LIST+=("${snap}")
    echo "  [${INDEX}] ${snap}"
    INDEX=$((INDEX + 1))
done <<< "${SNAPSHOTS}"

# ── Select Snapshot ──────────────────────────────────────────────────────────

if [ -n "${SNAPSHOT_NAME}" ]; then
    # Verify the specified snapshot exists
    if echo "${SNAPSHOTS}" | grep -qF "${SNAPSHOT_NAME}"; then
        log "Using specified snapshot: ${SNAPSHOT_NAME}"
        TARGET_SNAPSHOT="${SNAPSHOT_NAME}"
    else
        die "Specified snapshot '${SNAPSHOT_NAME}' not found in available snapshots."
    fi
else
    # Interactive: prompt for selection
    echo ""
    echo "Enter the number of the snapshot to restore (1-${#SNAPSHOT_LIST[@]}):"
    read -r selection

    if ! [[ "${selection}" =~ ^[0-9]+$ ]] || [ "${selection}" -lt 1 ] || [ "${selection}" -gt "${#SNAPSHOT_LIST[@]}" ]; then
        die "Invalid selection. Must be a number between 1 and ${#SNAPSHOT_LIST[@]}."
    fi

    TARGET_SNAPSHOT="${SNAPSHOT_LIST[$((selection - 1))]}"
fi

log "Target snapshot: ${TARGET_SNAPSHOT}"

# ── Safety Warning and Confirmation ──────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  RESTORE WARNING"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "  Container:  ${CONTAINER_NAME}"
echo "  Snapshot:   ${TARGET_SNAPSHOT}"
echo ""
echo "  This will REPLACE the current state of the container with"
echo "  the state saved in the snapshot above."
echo ""
echo "  Actions that will be taken:"
echo "    1. Stop the container (if running)"
echo "    2. Create a pre-restore snapshot (if container was running)"
echo "    3. Restore the selected snapshot"
echo "    4. Start the container"
echo ""
echo "  This operation CANNOT be undone once started."
echo "═══════════════════════════════════════════════════════════════"
echo ""

prompt_yes_no "Are you sure you want to restore '${TARGET_SNAPSHOT}' to '${CONTAINER_NAME}'?"

# ── Pre-Restore Safety Snapshot ──────────────────────────────────────────────

CONTAINER_RUNNING=false
if lxc info "${CONTAINER_NAME}" 2>/dev/null | grep -q "Status: Running"; then
    CONTAINER_RUNNING=true
    PRE_SNAPSHOT="pre-restore-$(date '+%Y%m%d-%H%M%S')"
    log "Container is running. Creating pre-restore snapshot '${PRE_SNAPSHOT}'..."
    run_or_dry lxc snapshot "${CONTAINER_NAME}" "${PRE_SNAPSHOT}" || {
        log "WARNING: Pre-restore snapshot creation failed. Proceeding with restore anyway."
    }
fi

# ── Stop Container ────────────────────────────────────────────────────────────

log "Stopping container '${CONTAINER_NAME}'..."
run_or_dry lxc stop "${CONTAINER_NAME}" --timeout 30 || {
    log "WARNING: Graceful stop timed out. Forcing stop..."
    run_or_dry lxc stop "${CONTAINER_NAME}" --force || {
        die "Failed to stop container '${CONTAINER_NAME}'. Aborting restore."
    }
}

# ── Restore ──────────────────────────────────────────────────────────────────

log "Restoring '${CONTAINER_NAME}' from snapshot '${TARGET_SNAPSHOT}'..."

if ! run_or_dry lxc restore "${CONTAINER_NAME}" "${TARGET_SNAPSHOT}"; then
    log "ERROR: Restore failed. Attempting to start container in current state..."
    run_or_dry lxc start "${CONTAINER_NAME}" || true
    die "Restore failed for '${CONTAINER_NAME}'. Container has been started (if possible)."
fi

log "Restore completed successfully."

# ── Start Container ──────────────────────────────────────────────────────────

log "Starting container '${CONTAINER_NAME}'..."
if ! run_or_dry lxc start "${CONTAINER_NAME}"; then
    die "Container failed to start after restore. Run 'lxc start ${CONTAINER_NAME}' manually to debug."
fi

log "Container '${CONTAINER_NAME}' is running after restore."

# ── Verification ─────────────────────────────────────────────────────────────

if [ "${DRY_RUN}" != "true" ]; then
    echo ""
    echo "Post-restore status:"
    lxc list "${CONTAINER_NAME}" --columns n,s 2>/dev/null
    echo ""
    log "Restore of '${TARGET_SNAPSHOT}' to '${CONTAINER_NAME}' completed and verified."
else
    log "DRY-RUN: Restore simulated. No changes made."
fi

echo ""
echo "Log: ${LOG_FILE}"
