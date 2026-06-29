#!/usr/bin/env bash
# ==========================================================
# approval-reject.sh — Reject a pending proposal
# ==========================================================
#
# Actions:
#   1. Move package from pending/ to rejected/
#   2. Append engineering journal entry
#
# Does NOT push. Does NOT revert the local commit.
# The local commit stays — the operator can git reset
# or handle it manually.
#
# Usage:
#   scripts/approval-reject.sh [YYYY-MM-DD-NNN]
#   scripts/approval-reject.sh YYYY-MM-DD-NNN "rejection reason"
#
# ==========================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PENDING_DIR="$REPO_ROOT/approval/pending"
REJECTED_DIR="$REPO_ROOT/approval/rejected"
JOURNAL="$REPO_ROOT/log/build-log.md"

log() { echo "  [approval-reject] $*"; }
die() { echo >&2 "  [approval-reject] FATAL: $*"; exit 1; }

# ---------------------------------------------------------
# Find the target package
# ---------------------------------------------------------

find_package() {
    local specified_id="${1:-}"

    if [ -n "$specified_id" ]; then
        if [ ! -d "$PENDING_DIR/$specified_id" ]; then
            die "Package not found in pending/: $specified_id"
        fi
        echo "$specified_id"
        return
    fi

    local latest
    latest="$(ls -1 "$PENDING_DIR" 2>/dev/null | sort -r | head -1)"
    if [ -z "$latest" ]; then
        die "No pending approval packages found."
    fi
    echo "$latest"
}

# ---------------------------------------------------------
# Move package to rejected/
# ---------------------------------------------------------

move_to_rejected() {
    local pkg_id="$1"
    local reason="${2:-No reason specified}"

    log "Moving package to rejected/..."
    mkdir -p "$REJECTED_DIR"

    # Write rejection reason before moving
    echo "Rejected: $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$PENDING_DIR/$pkg_id/rejection-reason.txt"
    echo "Reason: ${reason}" >> "$PENDING_DIR/$pkg_id/rejection-reason.txt"

    mv "$PENDING_DIR/$pkg_id" "$REJECTED_DIR/$pkg_id"

    if [ -d "$REJECTED_DIR/$pkg_id" ]; then
        log "Package moved to rejected/${pkg_id}"
    else
        die "Failed to move package. Check filesystem."
    fi
}

# ---------------------------------------------------------
# Append engineering journal entry
# ---------------------------------------------------------

append_journal() {
    local pkg_id="$1"
    local reason="${2:-No reason specified}"

    log "Appending engineering journal entry..."

    cat >> "$JOURNAL" <<EOF

---
## $(date +%Y-%m-%d) — Approval Package Rejected: ${pkg_id}

### Date
$(date +%Y-%m-%d)

### Source
\`#provenance: approval-pipeline\`

### Decision
Approval package **${pkg_id}** was rejected by operator.

### Reasoning
${reason}

### Changes Made
- Package moved from \`approval/pending/${pkg_id}\` to \`approval/rejected/${pkg_id}\`
- Rejection reason recorded
- No push performed
- Journal entry appended

### Lessons Learned
_Review rejection reason for improvements in next sprint._

### Follow-Up Actions
- [ ] Address rejection reason and create revised proposal if needed
EOF

    log "Journal entry appended."
}

# ---------------------------------------------------------
# Main
# ---------------------------------------------------------

main() {
    local pkg_id
    local reason="No reason specified"

    # Parse arguments: [PKG_ID] [REASON]
    if [[ $# -ge 1 ]]; then
        pkg_id="$(find_package "$1")"
        if [[ $# -ge 2 ]]; then
            reason="$2"
        fi
    else
        pkg_id="$(find_package)"
    fi

    log "Engineering Approval Pipeline — Reject"
    log "Package: ${pkg_id}"

    move_to_rejected "$pkg_id" "$reason"
    append_journal "$pkg_id" "$reason"

    log "==========================================="
    log "REJECTED: ${pkg_id}"
    log "Package archived: approval/rejected/${pkg_id}/"
    log "No push performed."
    log "==========================================="
}

main "$@"
