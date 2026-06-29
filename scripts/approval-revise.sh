#!/usr/bin/env bash
# ==========================================================
# approval-revise.sh — Reopen a proposal for changes
# ==========================================================
#
# Actions:
#   1. Keep the original proposal package in pending/
#   2. Reopen engineering work (no-op — already)
#   3. Create a new proposal package referencing the previous one
#
# Usage:
#   scripts/approval-revise.sh YYYY-MM-DD-NNN ["reason"]
#
# The script will use package
#   referencing the old one via proposal-link.txt
#
# ==========================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PENDING_DIR="$REPO_ROOT/approval/pending"
SCRIPTS_DIR="$REPO_ROOT/scripts"

log() { echo "  [approval-revise] $*"; }
die() { echo >&2 "  [approval-revise] FATAL: $*"; exit 1; }

# ---------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------

if [[ $# -lt 1 ]]; then
    die "Usage: $0 YYYY-MM-DD-NNN [\"reason for revision\"]"
fi

original_pkg_id="$1"
shift
revision_reason="${1:-Revision requested}"

if [ ! -d "$PENDING_DIR/$original_pkg_id" ]; then
    die "Original package not found: $original_pkg_id"
fi

log "Engineering Approval Pipeline — Revise"
log "Original: $original_pkg_id"
log "Reason: $revision_reason"

# ---------------------------------------------------------
# Generate new package referencing the original
# ---------------------------------------------------------

# Reuse the generate script with --reference flag
"$SCRIPTS_DIR/approval-generate.sh" --reference "$original_pkg_id" "$revision_reason"

log "==========================================="
log "REVISION STARTED"
log "Original package: $original_pkg_id (unchanged in pending/)"
log "New package generated (see output above)"
log "Edit files, then run: hermes approve"
log "==========================================="