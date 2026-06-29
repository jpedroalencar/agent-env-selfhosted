#!/usr/bin/env bash
# ==========================================================
# approval-generate.sh — Generate an Approval Package
# ==========================================================
#
# After a sprint is frozen, this script:
#   1. Verifies all tests pass (captures results)
#   2. Runs Repository Synchronization (git status)
#   3. Generates the Proposal Package:
#      - summary.md        — human‑readable summary
#      - changed-files.md  — list of changed files
#      - git-diff.patch     — full diff of staged changes
#      - proposal-link.txt  — reference to any previous proposal
#      - test-results.md   — pytest output
#   4. Stages every generated file
#   5. Creates a local Git commit
#   6. Generates the Approval Package (in approval/pending/)
#   7. Stops (enters WAITING_FOR_APPROVAL state)
#
# Usage:
#   scripts/approval-generate.sh ["optional commit message"]
#   scripts/approval-generate.sh --reference YYYY-MM-DD-NNN  # revise mode
#
# Deterministic: Running with the same repo state produces
# the same package (modulo timestamps in filenames and content).
# Restart‑safe: If a package already exists for today's date,
# increments the sequence number (NNN).
#
# ==========================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPROVAL_DIR="$REPO_ROOT/approval/pending"
SCRIPTS_DIR="$REPO_ROOT/scripts"

# ---------------------------------------------------------
# Helpers
# ---------------------------------------------------------
log() { echo "  [approval-generate] $*"; }
 die() { echo >&2 "  [approval-generate] FATAL: $*"; exit 1; }

# Generate YYYY-MM-DD-NNN package ID, incrementing NNN if needed
next_package_id() {
    local today
    today="$(date +%Y-%m-%d)"
    local n=1
    while [ -d "$APPROVAL_DIR/${today}-${n}" ]; do
        n=$((n + 1))
    done
    echo "${today}-${n}"
}

# ---------------------------------------------------------
# Phase 1 — Verify tests pass and capture results
# ---------------------------------------------------------
verify_tests() {
    log "Running test suite..."
    local result_file="${1}/test-results.md"
    if python3 -m pytest "$REPO_ROOT/tests/" -o 'addopts=' -q --tb=short > "$result_file" 2>&1; then
        log "All tests passed."
    else
        log "Tests failed – see $result_file"
        die "Test suite failed."
    fi
}

# ---------------------------------------------------------
# Phase 2 — Repository Synchronization
# ---------------------------------------------------------
sync_repository() {
    log "Checking repository state..."
    local dirty
    dirty="$(cd "$REPO_ROOT" && git status --porcelain)"
    if [ -z "$dirty" ]; then
        die "No changes to propose. Repository is clean."
    fi
    log "Found $(echo "$dirty" | wc -l) changed file(s)."
}

# ---------------------------------------------------------
# Phase 3 — Generate Proposal Package files
# ---------------------------------------------------------
generate_summary() {
    local pkg_dir="$1"
    local pkg_id="$2"
    local reference="$3"
    local commit_msg="$4"
    local branch
    branch="$(cd "$REPO_ROOT" && git rev-parse --abbrev-ref HEAD)"
    local commit_count
    commit_count="$(cd "$REPO_ROOT" && git rev-list --count HEAD)"
    local last_commit
    last_commit="$(cd "$REPO_ROOT" && git log --oneline -1)"

    cat > "$pkg_dir/summary.md" <<EOF
# Approval Package: ${pkg_id}

**Generated:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Branch:** ${branch}
**Base Commit:** ${last_commit}
**Total Commits:** ${commit_count}

## Commit Message

${commit_msg}

## Status

WAITING_FOR_APPROVAL
EOF

    if [ -n "$reference" ]; then
        echo "" >> "$pkg_dir/summary.md"
        echo "## Revision Of" >> "$pkg_dir/summary.md"
        echo "" >> "$pkg_dir/summary.md"
        echo "This proposal revises: \`${reference}\`" >> "$pkg_dir/summary.md"
    fi

    log "Generated summary.md"
}

generate_changed_files() {
    local pkg_dir="$1"
    {
        echo "# Changed Files"
        echo ""
        echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo ""
        echo "| Status | File |"
        echo "|--------|------|"
        cd "$REPO_ROOT" && git status --porcelain | while IFS= read -r line; do
            local status="${line:0:2}"
            local file="${line:3}"
            echo "| \`${status}\` | \`${file}\` |"
        done
    } > "$pkg_dir/changed-files.md"
    log "Generated changed-files.md"
}

generate_diff() {
    local pkg_dir="$1"
    cd "$REPO_ROOT" && git diff HEAD > "$pkg_dir/git-diff.patch"
    local diff_size
    diff_size="$(wc -c < "$pkg_dir/git-diff.patch")"
    log "Generated git-diff.patch (${diff_size} bytes)"
}

generate_proposal_link() {
    local pkg_dir="$1"
    local reference="$2"
    if [ -n "$reference" ]; then
        echo "Revises: ${reference}" > "$pkg_dir/proposal-link.txt"
        echo "Previous: ${reference}" >> "$pkg_dir/proposal-link.txt"
        log "Generated proposal-link.txt (references ${reference})"
    else
        echo "Original proposal (no prior reference)" > "$pkg_dir/proposal-link.txt"
        log "Generated proposal-link.txt (original)"
    fi
}

# ---------------------------------------------------------
# Phase 4 — Stage and commit generated files
# ---------------------------------------------------------
stage_and_commit() {
    local pkg_dir="$1"
    local pkg_id="$2"
    local commit_msg="$3"

    log "Staging approval package files..."
    cd "$REPO_ROOT"
    git add "$pkg_dir/"

    log "Staging all other changed files..."
    git add -A

    log "Creating local commit..."
    "$SCRIPTS_DIR/git-commit.sh" -m "${commit_msg}" 2>&1 || \
        die "git-commit.sh failed."
    log "Commit created successfully."
}

# ---------------------------------------------------------
# Phase 5 — Regenerate diff to include the commit itself
# ---------------------------------------------------------
update_diff_post_commit() {
    local pkg_dir="$1"
    cd "$REPO_ROOT" && git diff HEAD~1 > "$pkg_dir/git-diff.patch"
    log "Regenerated diff after commit."
}

# ---------------------------------------------------------
# Main
# ---------------------------------------------------------
main() {
    local commit_msg="${1:-Generated approval package}" 
    local reference=""
    # Detect optional --reference flag
    if [[ "$commit_msg" == --reference* ]]; then
        reference="${commit_msg#--reference }"
        commit_msg="${2:-Generated approval package}"
    fi

    local pkg_id
    pkg_id=$(next_package_id)
    local pkg_dir="$APPROVAL_DIR/$pkg_id"
    mkdir -p "$pkg_dir"

    log "Package ID: $pkg_id"
    # Phase 1 – test suite (captures results)
    verify_tests "$pkg_dir"
    # Phase 2 – repository check
    sync_repository
    # Phase 3 – generate files
    generate_summary "$pkg_dir" "$pkg_id" "$reference" "$commit_msg"
    generate_changed_files "$pkg_dir"
    generate_diff "$pkg_dir"
    generate_proposal_link "$pkg_dir" "$reference"
    # Phase 4 – stage & commit
    stage_and_commit "$pkg_dir" "$pkg_id" "$commit_msg"
    # Phase 5 – update diff after commit
    update_diff_post_commit "$pkg_dir"

    log "Approval package $pkg_id created under $pkg_dir"
}

main "$@"
