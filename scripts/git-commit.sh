#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# Platform Engineering Gateway — the single supported commit path.
# ══════════════════════════════════════════════════════════════
#
# Every Platform commit flows through this script. Direct `git commit`
# is unsupported. This is where identity, lint, tests, message validation,
# and verification all converge — one gate, one policy, one audit trail.
#
#   scripts/git-commit.sh "commit message"
#   scripts/git-commit.sh -m "commit message"
#   scripts/git-commit.sh -am "commit message"
#
# All arguments pass through to `git commit` unchanged.
#
# ── Commit Pipeline ───────────────────────────────────────
#
#   Phase 0 — Pre-commit hooks (future extension points)
#     → commit message validation  (conventional commits format)
#     → syntax check               (lint staged files)
#     → test run                   (run affected tests)
#
#   Phase 1 — Commit
#     → set deterministic author identity
#     → execute git commit
#
#   Phase 2 — Post-commit verification
#     → verify author/committer identity split
#     → (future) verify commit message format
#     → (future) push to remote
#
# ── Adding a hook ─────────────────────────────────────────
#
# Drop an executable script into scripts/hooks/pre-commit.d/
# or scripts/hooks/post-commit.d/. They run in alphabetical order.
# Any hook that exits non-zero blocks the pipeline.
#
# ══════════════════════════════════════════════════════════════

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="$REPO_ROOT/scripts/hooks"

# ─────────────────────────────────────────────────────────
# Phase 0 — Pre-commit hooks
# ─────────────────────────────────────────────────────────
run_hooks() {
    local hook_dir="$1"
    local phase_name="$2"

    if [ -d "$hook_dir" ]; then
        for hook in "$hook_dir"/*; do
            if [ -x "$hook" ]; then
                echo "  [$phase_name] $(basename "$hook")"
                "$hook" || {
                    echo >&2 "  [$phase_name] FAILED — commit blocked"
                    exit 1
                }
            fi
        done
    fi
}

run_hooks "$HOOKS_DIR/pre-commit.d" "pre-commit"

# ─────────────────────────────────────────────────────────
# Phase 1 — Commit with deterministic identity
# ─────────────────────────────────────────────────────────

# Author identity — hardcoded, never environment-dependent.
# Committer identity — from repo config (johnalencar-agent).
export GIT_AUTHOR_NAME="John P. Alencar"
export GIT_AUTHOR_EMAIL="johnpalencar@hotmail.com"

git commit "$@"

# ─────────────────────────────────────────────────────────
# Phase 2 — Post-commit verification
# ─────────────────────────────────────────────────────────

EXPECTED="Author: John P. Alencar <johnpalencar@hotmail.com> | Committer: johnalencar-agent <johnalencar-agent@users.noreply.github.com>"
ACTUAL=$(git log --format='Author: %an <%ae> | Committer: %cn <%ce>' -1)

if [ "$ACTUAL" != "$EXPECTED" ]; then
    echo >&2 "  IDENTITY VIOLATION — expected: $EXPECTED"
    echo >&2 "                         actual:   $ACTUAL"
    exit 2
fi

echo "  identity: $ACTUAL"

run_hooks "$HOOKS_DIR/post-commit.d" "post-commit"
