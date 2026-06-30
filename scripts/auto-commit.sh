#!/usr/bin/env bash
# ============================================================
# auto-commit.sh — Auto-commit relevant code changes
# ============================================================
# Stages and commits relevant files in the repository.
# Uses git-commit.sh wrapper to enforce identity.
# Post-commit hook (01-auto-push) then pushes to GitHub.
# GitHub Actions (auto-pr.yml) then creates a Draft PR.
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

log() { echo "  [auto-commit] $*"; }
die() { echo >&2 "  [auto-commit] FATAL: $*"; exit 1; }

# ---------------------------------------------------------
# Step 1 — Check for relevant changes
# ---------------------------------------------------------
RELEVANT_FILES=$(git status --porcelain | grep -E '\.(py|sh|yml|yaml|md|json|txt)$' | grep -v '^??' | head -50)

if [ -z "$RELEVANT_FILES" ]; then
    log "No relevant changes detected. Skipping."
    exit 0
fi

FILE_COUNT=$(echo "$RELEVANT_FILES" | wc -l)
log "Found $FILE_COUNT relevant file(s) to commit."

# ---------------------------------------------------------
# Step 2 — Stage relevant files
# ---------------------------------------------------------
# Stage tracked files with relevant extensions
git add *.py scripts/ .github/ docs/ *.md config/ 2>/dev/null || true

# Stage any new files in important directories
git add proposal/ approval/ 2>/dev/null || true

# Check if anything is staged
STAGED=$(git diff --cached --name-only)
if [ -z "$STAGED" ]; then
    log "No staged changes after filtering. Skipping."
    exit 0
fi

# ---------------------------------------------------------
# Step 3 — Generate commit message
# ---------------------------------------------------------
CHANGES=$(git diff --cached --stat | tail -1)
DATE=$(date +%Y-%m-%d)
SHORT_STAT=$(git diff --cached --stat | head -5 | tr '\n' '; ' | sed 's/; $//')

COMMIT_MSG="chore: auto-commit - ${DATE}

${SHORT_STAT}"

log "Commit message: $(echo "$COMMIT_MSG" | head -1)"

# ---------------------------------------------------------
# Step 4 — Commit using the wrapper
# ---------------------------------------------------------
"$REPO_ROOT/scripts/git-commit.sh" -m "$COMMIT_MSG" || die "git-commit.sh failed"

log "Commit created successfully."
log "Post-commit hook will auto-push to GitHub."
