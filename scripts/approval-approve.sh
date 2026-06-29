#!/usr/bin/env bash
# ==========================================================
# approval-approve.sh — Approve pending proposal + push
# ==========================================================
#
# Actions:
#   1. Verify current approval package exists and is valid
#   2. Execute git push
#   3. Move package from pending/ to approved/
#   4. Append engineering journal entry
#
# Usage:
#   scripts/approval-approve.sh [YYYY-MM-DD-NNN]
#
# If no package ID is given, approves the most recent
# pending package.
#
# ==========================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PENDING_DIR="$REPO_ROOT/approval/pending"
APPROVED_DIR="$REPO_ROOT/approval/approved"
JOURNAL="$REPO_ROOT/log/build-log.md"

log() { echo "  [approval-approve] $*"; }
die() { echo >&2 "  [approval-approve] FATAL: $*"; exit 1; }

# ---------------------------------------------------------
# Find the target package
# ---------------------------------------------------------

find_package() {
    local specified_id="${1:-}"

    if [ -n "$specified_id" ]; then
        if [ ! -d "$PENDING_DIR/$specified_id" ]; then
            die "Package not found: $specified_id"
        fi
        echo "$specified_id"
        return
    fi

    # Find most recent pending package
    local latest
    latest="$(ls -1 "$PENDING_DIR" 2>/dev/null | sort -r | head -1)"
    if [ -z "$latest" ]; then
        die "No pending approval packages found."
    fi
    echo "$latest"
}

# ---------------------------------------------------------
# Verify package integrity
# ---------------------------------------------------------

verify_package() {
    local pkg_id="$1"
    local pkg_dir="$PENDING_DIR/$pkg_id"

    log "Verifying package: ${pkg_id}"

    local required_files="summary.md changed-files.md git-diff.patch proposal-link.txt"
    local missing=0

    for f in $required_files; do
        if [ ! -f "$pkg_dir/$f" ]; then
            log "MISSING: $f"
            missing=$((missing + 1))
        else
            log "  ✓ $f"
        fi
    done

    if [ "$missing" -gt 0 ]; then
        die "Package is incomplete (${missing} file(s) missing). Reject or revise instead."
    fi

    # Verify it's actually pending (exists in pending/)
    if [ ! -d "$pkg_dir" ]; then
        die "Package directory does not exist in pending/."
    fi

    log "Package verified."
}

# ---------------------------------------------------------
# Execute git push
# ---------------------------------------------------------

execute_push() {
    log "Pushing to remote..."
    cd "$REPO_ROOT"
    if git push origin HEAD 2>&1; then
        log "Push successful."
    else
        die "git push failed. Package remains in pending/."
    fi
}

# ---------------------------------------------------------
# Move package to approved/
# ---------------------------------------------------------

move_to_approved() {
    local pkg_id="$1"

    log "Moving package to approved/..."
    mkdir -p "$APPROVED_DIR"
    mv "$PENDING_DIR/$pkg_id" "$APPROVED_DIR/$pkg_id"

    if [ -d "$APPROVED_DIR/$pkg_id" ]; then
        log "Package moved to approved/${pkg_id}"
    else
        die "Failed to move package. Check filesystem."
    fi
}

# ---------------------------------------------------------
# Append engineering journal entry
# ---------------------------------------------------------

append_journal() {
    local pkg_id="$1"

    log "Appending engineering journal entry..."

    cat >> "$JOURNAL" <<EOF

---
## $(date +%Y-%m-%d) — Approval Package Approved: ${pkg_id}

### Date
$(date +%Y-%m-%d)

### Source
\`#provenance: approval-pipeline\`

### Decision
Approval package **${pkg_id}** was approved and pushed to remote.

### Reasoning
Human operator reviewed the proposal package and approved. Changes pushed via \`git push\`.

### Changes Made
- Package moved from \`approval/pending/${pkg_id}\` to \`approval/approved/${pkg_id}\`
- \`git push\` executed successfully
- Journal entry appended

### Lessons Learned
_No new lessons in this approval cycle._

### Follow-Up Actions
None at this time.
EOF

    log "Journal entry appended."
}

# ---------------------------------------------------------
# Main
# ---------------------------------------------------------

main() {
    local pkg_id
    pkg_id="$(find_package "${1:-}")"

    log "Engineering Approval Pipeline — Approve"
    log "Package: ${pkg_id}"

    verify_package  "$pkg_id"
    execute_push
    move_to_approved "$pkg_id"
    append_journal  "$pkg_id"

    log "==========================================="
    log "APPROVED: ${pkg_id}"
    log "Pushed to remote."
    log "Package archived: approval/approved/${pkg_id}/"
    log "==========================================="
}

main "$@"
