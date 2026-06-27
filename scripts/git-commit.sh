#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────
# Git Identity Wrapper
# ──────────────────────────────────────────────────────────
# Every Platform commit flows through this script.
#
# Committer = johnalencar-agent  (set by repo config)
# Author    = John P. Alencar    (set below, always)
#
# Usage:
#   scripts/git-commit.sh "commit message"
#   scripts/git-commit.sh -m "commit message"
#   scripts/git-commit.sh -am "commit message"
#   scripts/git-commit.sh --amend --no-edit
#
# All arguments pass through to `git commit` unchanged.
# ──────────────────────────────────────────────────────────

set -euo pipefail

# ── Author Identity (deterministic, never environment-dependent) ──
export GIT_AUTHOR_NAME="John P. Alencar"
export GIT_AUTHOR_EMAIL="johnpalencar@hotmail.com"

# ── Commit ───────────────────────────────────────────────
git commit "$@"

# ── Verify ───────────────────────────────────────────────
LAST_COMMIT=$(git log --format='Author: %an <%ae> | Committer: %cn <%ce>' -1)

EXPECTED="Author: John P. Alencar <johnpalencar@hotmail.com> | Committer: johnalencar-agent <johnalencar-agent@users.noreply.github.com>"

if [ "$LAST_COMMIT" != "$EXPECTED" ]; then
    echo >&2 ""
    echo >&2 "  IDENTITY VIOLATION"
    echo >&2 "  ──────────────────"
    echo >&2 "  Expected:  $EXPECTED"
    echo >&2 "  Actual:    $LAST_COMMIT"
    echo >&2 ""
    echo >&2 "  The commit was created but its identity does not match policy."
    echo >&2 "  This is an architectural violation. Investigate before pushing."
    echo >&2 ""
    exit 2
fi

echo "  Identity verified: $EXPECTED"
