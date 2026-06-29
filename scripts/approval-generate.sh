#!/usr/bin/env bash
# ==========================================================
# approval-generate.sh — Generate an Approval Package
# ==========================================================
#
# After a sprint is frozen, this script:
#   1. Verifies all tests pass
#   2. Runs Repository Synchronization (git status)
#   3. Generates the Proposal Package:
#      - summary.md        — human-readable summary
#      - changed-files.md  — list of changed files
#      - git-diff.patch     — full diff of staged changes
#      - proposal-link.txt  — reference to any previous proposal
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
# Restart-safe: If a package already exists for today's date,
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
# Phase 1 — Verify tests pass
# ---------------------------------------------------------

verify_tests() {
    log "Running test suite..."
    if python3 -m pytest "$REPO_ROOT/tests/" -o 'addopts=' -q --tb=short 2>&1; then
        log "All tests passed."
    else
        die "Tests failed. Fix before generating approval package."
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
    # Stage everything that's modified/untracked
    git add -A

    log "Creating local commit..."
    "$SCRIPTS_DIR/git-commit.sh" -m "${commit_msg}" 2>&1 || \
        die "git-commit.sh failed. See errors above."

    log "Commit created successfully."
}

# ---------------------------------------------------------
# Phase 5 — Regenerate diff to include the commit itself
# ---------------------------------------------------------

update_diff_post_commit() {
    local pkg_dir="$1"

    # Now regenerate the diff to include the approval package files
    # that were just committed
    cd "$REPO_ROOT" && git diff HEAD~1 > "$pkg_dir/git-diff.patch"
    log "Updated git-diff.patch to include committed changes"
}

# ---------------------------------------------------------
# Main
# ---------------------------------------------------------

main() {
    local reference=""
    local commit_msg="chore: approval package — sprint completion"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reference)
                reference="$2"
                shift 2
                ;;
            *)
                commit_msg="$1"
                shift
                ;;
        esac
    done

    log "Engineering Approval Pipeline — Generate"
    log "Repository: $REPO_ROOT"

    # Phase 1: Verify tests
    verify_tests

    # Phase 2: Sync repository
    sync_repository

    # Phase 3: Generate package
    local pkg_id
    pkg_id="$(next_package_id)"
    local pkg_dir="$APPROVAL_DIR/$pkg_id"

    log "Creating package: ${pkg_id}"
    mkdir -p "$pkg_dir"

    generate_summary    "$pkg_dir" "$pkg_id" "$reference" "$commit_msg"
    generate_changed_files "$pkg_dir"
    generate_diff       "$pkg_dir"
    generate_proposal_link "$pkg_dir" "$reference"

    # Phase 4: Stage and commit
    stage_and_commit "$pkg_dir" "$pkg_id" "$commit_msg"

    # Phase 5: Update diff post-commit
    update_diff_post_commit "$pkg_dir"

    log "==========================================="
    log "Package: ${pkg_id}"
    log "Location: approval/pending/${pkg_id}/"
    log "State: WAITING_FOR_APPROVAL"
    log "==========================================="
    log ""
    log "Next steps:"
    log "  hermes approve   — push to remote"
    log "  hermes reject    — move to rejected/"
    log "  hermes revise    — reopen for changes"

    # Return the package ID for programmatic use
    echo "$pkg_id"
}

main "$@"
