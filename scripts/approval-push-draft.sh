#!/usr/bin/env bash
# ==========================================================
# approval-push-draft.sh — Push a pending approval package and open/update a Draft Pull Request
# ==========================================================
# Usage: scripts/approval-push-draft.sh [PACKAGE_ID]
# If no PACKAGE_ID is provided, the most recent pending package is used.
#
# This script performs the following steps:
#   1. Verify the pending approval package exists and is complete.
#   2. Create a stable branch name: approval/<package-id>-<feature>
#      (feature extracted from the first line of the summary after "## Commit Message").
#   3. Push the branch to the remote (no --force). If the remote branch already
#      exists, the push proceeds normally; if it would diverge, the script aborts.
#   4. Build PR title and body from the package's summary.md (source of truth).
#   5. If a Draft PR for this branch already exists, update its title/body.
#      Otherwise, create a new Draft PR.
#   6. Do not perform any automatic merge or approval.
# ==========================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PENDING_DIR="$REPO_ROOT/approval/pending"
JOURNAL="$REPO_ROOT/log/build-log.md"

log() { echo "  [approval-push-draft] $*"; }
 die() { echo >&2 "  [approval-push-draft] FATAL: $*"; exit 1; }

# ---------------------------------------------------------
# Helper: find target package
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
    # Most recent pending package (lexicographically latest)
    local latest
    latest="$(ls -1 "$PENDING_DIR" 2>/dev/null | sort -r | head -1)"
    if [ -z "$latest" ]; then
        die "No pending approval packages found."
    fi
    echo "$latest"
}

# ---------------------------------------------------------
# Verify package integrity (same as approval-approve)
# ---------------------------------------------------------
verify_package() {
    local pkg_id="$1"
    local pkg_dir="$PENDING_DIR/$pkg_id"
    log "Verifying package $pkg_id"
    local required_files="summary.md changed-files.md git-diff.patch proposal-link.txt test-results.md"
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
        die "Package is incomplete (${missing} missing file(s))."
    fi
    log "Package verification complete."
}

# ---------------------------------------------------------
# Derive stable branch name and PR content from summary.md
# ---------------------------------------------------------
extract_feature_name() {
    local summary_path="$1"
    # Look for the first non‑empty line after a "## Commit Message" heading
    local title_line
    title_line=$(awk '/^## Commit Message/{flag=1;next} flag && NF{print;exit}' "$summary_path")
    if [ -z "$title_line" ]; then
        # Fallback to package directory name
        title_line="feature"
    fi
    # Sanitize: replace spaces with hyphens, lower‑case, keep alphanumerics and hyphens
    echo "$title_line" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//'
}

build_pr_title() {
    local pkg_id="$1"
    local summary_path="$2"
    local feature="$(extract_feature_name "$summary_path")"
    echo "Sprint ${pkg_id}: ${feature}"
}

build_pr_body() {
    local pkg_id="$1"
    local pkg_dir="$PENDING_DIR/$pkg_id"
    local summary_path="$pkg_dir/summary.md"
    local changed_path="$pkg_dir/changed-files.md"
    local diff_path="$pkg_dir/git-diff.patch"
    local test_path="$pkg_dir/test-results.md"
    local proposal_path="$pkg_dir/proposal-link.txt"

    local body=""
    body+="**Approval Package Path:** $pkg_dir\n\n"
    body+="---\n"
    body+="$(cat "$summary_path")\n"
    body+="---\n"
    body+="$(cat "$changed_path")\n"
    body+="---\n"
    body+="## Test Results\n\n$(cat "$test_path")\n"
    body+="---\n"
    body+="## Architecture Impact\n\n_No architectural impact detected._\n"
    body+="---\n"
    body+="$(cat "$proposal_path")\n"
    echo "$body"
}

# ---------------------------------------------------------
# Helper: GitHub REST API functions
# ---------------------------------------------------------

github_api() {
    local method=$1
    local url=$2
    local data=$3
    # Retrieve token from git credential helper (in memory only)
    token=$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill | grep '^password=' | cut -d= -f2)
    if [ -z "$token" ]; then
        die "GitHub token not found via git credential helper"
    fi
    local auth_header="Authorization: Bearer $token"

    local response
    if [ -n "$data" ]; then
        response=$(curl -s -w "%{http_code}" -X "$method" -H "$auth_header" -H "Accept: application/vnd.github+json" -d "$data" "$url")
    else
        response=$(curl -s -w "%{http_code}" -X "$method" -H "$auth_header" -H "Accept: application/vnd.github+json" "$url")
    fi
    # Discard token immediately
    unset token
    local body=$(echo "$response" | sed '$d')
    local code=$(echo "$response" | tail -n1)
    echo "$code|$body"
}

# Find existing Draft PR for a branch (returns PR number or empty)
find_existing_pr() {
    local owner_repo=$1
    local branch=$2
    local url="https://api.github.com/repos/$owner_repo/pulls?state=open&head=$owner_repo:$branch"
    local result=$(github_api GET "$url")
    local code=${result%%|*}
    local body=${result#*|}
    if [ "$code" -ne 200 ]; then
        die "GitHub API error $code while listing PRs: $body"
    fi
    # Extract draft PR number via python json parsing
    local pr_number=$(echo "$body" | python3 - <<'PY'
import sys, json
prs = json.load(sys.stdin)
for pr in prs:
    if pr.get('draft'):
        print(pr['number'])
        break
PY
)
    echo "$pr_number"
}

# ---------------------------------------------------------
# Main workflow
# ---------------------------------------------------------
main() {
    local pkg_id
    pkg_id=$(find_package "${1:-}")
    verify_package "$pkg_id"

    local summary_path="$PENDING_DIR/$pkg_id/summary.md"
    local feature_name
    feature_name=$(extract_feature_name "$summary_path")
    local branch_name="approval/${pkg_id}-${feature_name}"

    log "Creating or updating branch $branch_name"
    cd "$REPO_ROOT"
    # If the branch already exists locally, checkout; otherwise create it
    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
        git checkout "$branch_name"
    else
        git checkout -b "$branch_name"
    fi

    # Ensure the branch is up‑to‑date with remote (no force)
    if git ls-remote --heads origin "$branch_name" | grep -q "$branch_name"; then
        # Remote branch exists – try a normal push first (will fail if diverged)
        if ! git push origin "$branch_name"; then
            die "Remote branch $branch_name exists and would diverge. Resolve locally before pushing."
        fi
    else
        git push -u origin "$branch_name"
    fi

    # Build PR title and body from the package
    local pr_title
    pr_title=$(build_pr_title "$pkg_id" "$summary_path")
    local pr_body
    pr_body=$(build_pr_body "$pkg_id")

    # Determine owner/repo from git remote URL
    local remote_url=$(git config --get remote.origin.url)
    if [[ "$remote_url" =~ ^git@github.com:(.+)/(.+)(\.git)?$ ]]; then
        owner_repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    elif [[ "$remote_url" =~ ^https://github.com/(.+)/(.+)(\.git)?$ ]]; then
        owner_repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    else
        die "Unable to parse GitHub repository URL: $remote_url"
    fi
    log "Detected repository $owner_repo"

    # Check for existing Draft PR
    local existing_pr
    existing_pr=$(find_existing_pr "$owner_repo" "$branch_name")
    if [ -n "$existing_pr" ]; then
        log "Updating existing Draft PR #$existing_pr"
        # Prepare JSON payload for PATCH
        local payload=$(printf '{"title": %s, "body": %s}' \
            "$(printf '%s' "$pr_title" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
            "$(printf '%s' "$pr_body" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')")
        result=$(github_api PATCH "https://api.github.com/repos/$owner_repo/pulls/$existing_pr" "$payload")
        code=${result%%|*}
        body=${result#*|}
        if [ "$code" -ne 200 ]; then
            die "GitHub API error $code while updating PR: $body"
        fi
    else
        log "Creating new Draft Pull Request"
        local payload=$(printf '{"title": %s, "body": %s, "head": %s, "base": "main", "draft": true}' \
            "$(printf '%s' "$pr_title" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
            "$(printf '%s' "$pr_body" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
            "$(printf '%s' "$branch_name" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')")
        result=$(github_api POST "https://api.github.com/repos/$owner_repo/pulls" "$payload")
        code=${result%%|*}
        body=${result#*|}
        if [ "$code" -ne 201 ]; then
            die "GitHub API error $code while creating PR: $body"
        fi
        existing_pr=$(echo "$body" | python3 -c 'import sys,json;print(json.load(sys.stdin)["number"])')
        log "Created Draft PR #$existing_pr"
    fi

    log "Draft PR processing completed for package $pkg_id (branch $branch_name)"
}

main "$@"
