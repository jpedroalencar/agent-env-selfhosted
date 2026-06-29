#!/usr/bin/env bash
# ==========================================================
# approval-sync.sh — Idempotent migration to ensure every pending approval package has a Draft PR
# ==========================================================
# Usage: scripts/approval-sync.sh
#
# This script scans all directories under approval/pending/ and for each package:
#   * Checks whether a Draft Pull Request already exists for the stable branch name
#     (approval/<package-id>-<feature>)
#   * If no Draft PR exists, it invokes approval-push-draft.sh to create one.
#   * Packages that already have a Draft PR are skipped.
#   * The script is safe to run multiple times; it will never create duplicate PRs.
#
# No background services, schedulers, or external workflow engines are used.
# ==========================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PENDING_DIR="$REPO_ROOT/approval/pending"
SCRIPTS_DIR="$REPO_ROOT/scripts"

log() { echo "  [approval-sync] $*"; }
 die() { echo >&2 "  [approval-sync] FATAL: $*"; exit 1; }

# ---------------------------------------------------------
# Helper: Determine if a Draft PR already exists for a given branch
# ---------------------------------------------------------
pr_exists_for_branch() {
    local branch_name="$1"
    # gh pr list returns PR numbers for open Draft PRs on the branch
    local pr_num
    pr_num=$(gh pr list --state open --head "$branch_name" --json number,isDraft -q "[?isDraft==\`true\`].number" | head -1 || true)
    if [ -n "$pr_num" ]; then
        echo "yes"
    else
        echo "no"
    fi
}

# ---------------------------------------------------------
# Main migration loop
# ---------------------------------------------------------
main() {
    if [ ! -d "$PENDING_DIR" ]; then
        die "Pending approval directory not found: $PENDING_DIR"
    fi

    log "Scanning pending approval packages..."
    for pkg_dir in "$PENDING_DIR"/*; do
        [ -d "$pkg_dir" ] || continue
        pkg_id=$(basename "$pkg_dir")
        log "Processing package $pkg_id"
        # Build stable branch name using same logic as approval-push-draft.sh
        summary_path="$pkg_dir/summary.md"
        if [ ! -f "$summary_path" ]; then
            log "  Missing summary.md, skipping package."
            continue
        fi
        # Extract feature name (same function as in push script)
        feature_name=$(awk '/^## Commit Message/{flag=1;next} flag && NF{print;exit}' "$summary_path" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')
        if [ -z "$feature_name" ]; then
            feature_name="feature"
        fi
        branch_name="approval/${pkg_id}-${feature_name}"
        # Check if a Draft PR already exists for this branch
        if [ "$(pr_exists_for_branch "$branch_name")" = "yes" ]; then
            log "  Draft PR already exists for branch $branch_name, skipping."
            continue
        fi
        # No Draft PR – create/update via approval-push-draft.sh
        log "  No Draft PR found, invoking approval-push-draft.sh for $pkg_id"
        "$SCRIPTS_DIR/approval-push-draft.sh" "$pkg_id" || log "  Failed to create Draft PR for $pkg_id"
    done
    log "Approval sync completed."
}

main "$@"
