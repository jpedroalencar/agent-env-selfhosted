#!/usr/bin/env bash
# ==========================================================
# approval-pipeline.sh — Full GitHub Approval Pipeline for a sprint
# ==========================================================
# Usage: scripts/approval-pipeline.sh [COMMIT_MESSAGE]
#
# This script performs the complete approval workflow for a sprint:
#   1. Generates an approval package (tests, diff, summary, etc.)
#   2. Creates a dedicated branch from the current commit
#   3. Pushes the branch using the Hermes GitHub account
#   4. Opens a Draft Pull Request against the "main" branch
#
# The script is deterministic and does not run any background services.
# No automatic merge or approval is performed.
# ==========================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"

log() { echo "  [approval-pipeline] $*"; }
die() { echo >&2 "  [approval-pipeline] FATAL: $*"; exit 1; }

# ---------------------------------------------------------
# Step 1 – Generate approval package
# ---------------------------------------------------------
log "Generating approval package..."
# Forward any commit message argument to approval-generate.sh
"$SCRIPTS_DIR/approval-generate.sh" "${1:-}" || die "approval-generate.sh failed"

# ---------------------------------------------------------
# Step 2 – Push draft PR (branch creation, push, PR creation)
# ---------------------------------------------------------
log "Pushing Draft Pull Request..."
"$SCRIPTS_DIR/approval-push-draft.sh" || die "approval-push-draft.sh failed"

log "GitHub Approval Pipeline completed successfully."
