#!/usr/bin/env bash
# ============================================================
# sprint-finalize.sh — Consolidate sprint commits before review
# ============================================================
# Squashes all commits on the current sprint branch into a
# single clean commit, preserving correct authorship.
#
# Usage:
#   scripts/sprint-finalize.sh ["commit message"]
#
# The script:
#   1. Verifies we're on a sprint/ branch
#   2. Counts commits ahead of main
#   3. Squashes all into one commit (preserves author)
#   4. Force pushes the consolidated branch
#   5. PR automatically updates on GitHub
#
# After this, click "Approve" on the PR to merge.
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

log() { echo "  [sprint-finalize] $*"; }
die() { echo >&2 "  [sprint-finalize] FATAL: $*"; exit 1; }

# ---------------------------------------------------------
# Step 1 — Verify we're on a sprint branch
# ---------------------------------------------------------
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")

if [ -z "$BRANCH" ]; then
    die "Not on a branch (detached HEAD)."
fi

if [[ ! "$BRANCH" =~ ^sprint/ ]]; then
    die "Not on a sprint branch (current: $BRANCH). Run this on a sprint/* branch."
fi

log "Branch: $BRANCH"

# ---------------------------------------------------------
# Step 2 — Count commits ahead of main
# ---------------------------------------------------------
git fetch origin main --quiet 2>/dev/null || true

AHEAD=$(git rev-list --count origin/main..HEAD 2>/dev/null || echo "0")
BEHIND=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo "0")

if [ "$AHEAD" -eq 0 ]; then
    die "No commits ahead of main. Nothing to consolidate."
fi

if [ "$BEHIND" -gt 0 ]; then
    die "Branch is $BEHIND commit(s) behind main. Rebase first."
fi

log "Commits ahead of main: $AHEAD"

# ---------------------------------------------------------
# Step 3 — Build consolidated commit message
# ---------------------------------------------------------
# Collect all commit messages
MESSAGES=$(git log --format='%s' origin/main..HEAD | tac)

# Use custom message if provided, otherwise auto-generate
if [ -n "${1:-}" ]; then
    COMMIT_MSG="$1"
else
    # --- Infer Conventional-Commits type(scope) from the diff ---
    HAS_TESTS=0; HAS_DOCS=0; HAS_CI=0; HAS_CODE=0; HAS_NEW=0
    CHANGED=$(git diff --name-only origin/main...HEAD 2>/dev/null || true)
    if git diff --name-only --diff-filter=A origin/main...HEAD 2>/dev/null | grep -q .; then HAS_NEW=1; fi
    SCOPES=""
    HAS_TESTS=0; HAS_DOCS=0; HAS_CI=0; HAS_CODE=0; HAS_NEW=0
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        case "$f" in
            tests/*|*_test.py|test_*.py) HAS_TESTS=1 ;;
            docs/*|*.md) HAS_DOCS=1 ;;
            .github/*) HAS_CI=1 ;;
            pilot/*|adapters/*) HAS_CODE=1 ;;
        esac
        case "$f" in
            pilot/*) SCOPES="${SCOPES} platform" ;;
            adapters/*) SCOPES="${SCOPES} adapter" ;;
            .github/*) SCOPES="${SCOPES} ci" ;;
            scripts/*) SCOPES="${SCOPES} scripts" ;;
            docs/*|*.md) SCOPES="${SCOPES} docs" ;;
        esac
    done <<< "$CHANGED"
    SCOPE=$(echo "$SCOPES" | tr ' ' '\n' \
        | awk 'NF&&!seen[$0]++' \
        | awk 'BEGIN{o["platform"]=1;o["adapter"]=2;o["ci"]=3;o["scripts"]=4;o["docs"]=5} {print (o[$0]?o[$0]:9)" "$0}' \
        | sort -n | cut -d' ' -f2 | head -2 | paste -sd, -)

    if [ "$HAS_TESTS" -eq 1 ] && [ "$HAS_CODE" -eq 0 ] && [ "$HAS_CI" -eq 0 ]; then
        TYPE="test"
    elif [ "$HAS_CI" -eq 1 ] && [ "$HAS_CODE" -eq 0 ] && [ "$HAS_DOCS" -eq 0 ]; then
        TYPE="ci"
    elif [ "$HAS_DOCS" -eq 1 ] && [ "$HAS_CODE" -eq 0 ] && [ "$HAS_CI" -eq 0 ]; then
        TYPE="docs"
    elif [ "$HAS_CODE" -eq 1 ] && [ "$HAS_NEW" -eq 1 ]; then
        TYPE="feat"
    else
        TYPE="fix"
    fi

    if [ -z "$SCOPE" ]; then
        COMMIT_MSG="${TYPE}: ${BRANCH}"
    else
        COMMIT_MSG="${TYPE}(${SCOPE}): ${BRANCH}"
    fi
    # Append the per-commit breakdown so the human can refine at review
    COMMIT_MSG="${COMMIT_MSG}

Consolidated from $AHEAD commits:

$(echo "$MESSAGES" | sed 's/^/- /')"
fi

log "Consolidated commit message:"
echo "$COMMIT_MSG" | sed 's/^/    /'

# ---------------------------------------------------------
# Step 4 — Squash all commits into one
# ---------------------------------------------------------
log "Squashing $AHEAD commits..."

# Get the merge base with main
MERGE_BASE=$(git merge-base origin/main HEAD)

# Soft reset to merge base (keeps all changes staged)
git reset --soft "$MERGE_BASE"

# Create new commit with correct authorship
# Author: John P. Alencar (the human)
# Committer: johnalencar-agent (the agent)
GIT_AUTHOR_NAME="John P. Alencar"
GIT_AUTHOR_EMAIL="johnpalencar@hotmail.com"
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL

git commit -m "$COMMIT_MSG"

log "Consolidated into 1 commit."

# ---------------------------------------------------------
# Step 5 — Force push
# ---------------------------------------------------------
log "Force pushing consolidated branch..."
git push --force origin "$BRANCH" 2>&1

log "Done! Branch $BRANCH consolidated and pushed."
log ""
log "Next step: Approve the PR on GitHub to merge."
log "  https://github.com/jpedroalencar/agent-env-selfhosted/pulls"
