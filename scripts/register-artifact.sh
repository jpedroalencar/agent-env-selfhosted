#!/usr/bin/env bash
#===============================================================================
# register-artifact.sh
#
# Registers a substantive artifact in the Knowledge Vault.
#
# Validates metadata, prevents duplicate registrations, injects YAML frontmatter
# into the artifact file, and appends an entry to artifacts/index.md.
#
# Designed to be called by persona agents (Research Analyst, Financial Analyst)
# immediately after generating a substantive artifact.
#
# Usage:
#   ./scripts/register-artifact.sh \
#       --persona <persona> \
#       --title "Artifact Title" \
#       --status <draft|verified> \
#       --tags "tag1, tag2" \
#       --freshness <30|90> \
#       --summary "One-line summary." \
#       --path "artifacts/<persona>/filename.md"
#
# Required arguments:
#   --persona    — One of: research-analyst, financial-analyst (Phase 1), dev, operations-manager
#   --title      — Human-readable artifact title
#   --status     — draft or verified
#   --tags       — Comma-separated list of keywords
#   --freshness  — Number of days before stale (30 for fast-moving, 90 for stable)
#   --summary    — One-line summary of the artifact's content
#   --path       — Relative path from repo root to the artifact file
#
# Environment:
#   ARTIFACTS_INDEX  — Override path to the vault index (default: artifacts/index.md)
#   LOG_DIR          — Override log directory (default: .hermes/vault-logs)
#   GIT_ROOT         — Override repo root (default: auto-detect from script location)
#
# Exit codes:
#   0  — Registration successful
#   1  — Invalid arguments or missing required field
#   2  — Duplicate registration (same title + persona already in index)
#   3  — Artifact file not found at --path
#   4  — Index file write failure
#   5  — Frontmatter injection failure
#   6  — Metadata validation failure
#===============================================================================

set -euo pipefail

# ── Auto-detect repo root ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${GIT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

INDEX_FILE="${ARTIFACTS_INDEX:-${REPO_ROOT}/artifacts/index.md}"
LOG_DIR="${LOG_DIR:-${REPO_ROOT}/.hermes/vault-logs}"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S UTC')
DATE_ONLY=$(date '+%Y-%m-%d')
LOGFILE="${LOG_DIR}/register-$(date '+%Y%m%d%H%M%S').log"

# ── Arg Parsing ──────────────────────────────────────────────────────────────
PERSONA=""
TITLE=""
STATUS=""
TAGS=""
FRESHNESS=""
SUMMARY=""
PATH_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --persona)    PERSONA="$2";    shift 2 ;;
        --title)      TITLE="$2";      shift 2 ;;
        --status)     STATUS="$2";     shift 2 ;;
        --tags)       TAGS="$2";       shift 2 ;;
        --freshness)  FRESHNESS="$2";  shift 2 ;;
        --summary)    SUMMARY="$2";    shift 2 ;;
        --path)       PATH_ARG="$2";   shift 2 ;;
        *)  echo "ERROR: Unknown option: $1" >&2
            echo "Usage: $0 --persona <p> --title <t> --status <s> --tags <t> --freshness <n> --summary <s> --path <p>" >&2
            exit 1
            ;;
    esac
done

# ── Helper: Log a failure and exit ────────────────────────────────────────────
fail() {
    local exit_code="$1"
    local message="$2"
    {
        echo "[${TIMESTAMP}] FAILURE exit=${exit_code}: ${message}"
        echo "  persona=${PERSONA}"
        echo "  title=${TITLE}"
        echo "  status=${STATUS}"
        echo "  tags=${TAGS}"
        echo "  freshness=${FRESHNESS}"
        echo "  summary=${SUMMARY}"
        echo "  path=${PATH_ARG}"
    } >> "$LOGFILE"
    echo "REGISTRATION FAILED: ${message}" >&2
    echo "Log: ${LOGFILE}" >&2
    exit "$exit_code"
}

# ── Validation ────────────────────────────────────────────────────────────────

VALID_PERSONAS=("research-analyst" "financial-analyst" "dev" "operations-manager")

# Check all required fields are present
if [ -z "$PERSONA" ];   then fail 1 "Missing required: --persona"; fi
if [ -z "$TITLE" ];     then fail 1 "Missing required: --title"; fi
if [ -z "$STATUS" ];    then fail 1 "Missing required: --status"; fi
if [ -z "$TAGS" ];      then fail 1 "Missing required: --tags"; fi
if [ -z "$FRESHNESS" ]; then fail 1 "Missing required: --freshness"; fi
if [ -z "$SUMMARY" ];   then fail 1 "Missing required: --summary"; fi
if [ -z "$PATH_ARG" ];  then fail 1 "Missing required: --path"; fi

# Validate persona
VALID=false
for p in "${VALID_PERSONAS[@]}"; do
    if [ "$p" = "$PERSONA" ]; then
        VALID=true
        break
    fi
done
if [ "$VALID" = false ]; then
    fail 6 "Invalid persona '${PERSONA}'. Must be one of: ${VALID_PERSONAS[*]}"
fi

# Validate status
if [ "$STATUS" != "draft" ] && [ "$STATUS" != "verified" ]; then
    fail 6 "Invalid status '${STATUS}'. Must be 'draft' or 'verified'."
fi

# Validate freshness
if ! [[ "$FRESHNESS" =~ ^[0-9]+$ ]]; then
    fail 6 "Invalid freshness_days '${FRESHNESS}'. Must be a positive integer."
fi

# Validate artifact file exists
FULL_PATH="${REPO_ROOT}/${PATH_ARG}"
if [ ! -f "$FULL_PATH" ]; then
    fail 3 "Artifact file not found: ${FULL_PATH}"
fi

# ── Duplicate Check ──────────────────────────────────────────────────────────

if [ -f "$INDEX_FILE" ]; then
    # Search for existing entry with same title and persona (case-insensitive)
    if grep -qi "|.*${TITLE}.*${PERSONA}" "$INDEX_FILE" 2>/dev/null; then
        fail 2 "Duplicate registration: '${TITLE}' already registered for '${PERSONA}' in ${INDEX_FILE}"
    fi
fi

# ── Inject YAML Frontmatter ──────────────────────────────────────────────────

# Check if frontmatter already exists
if head -1 "$FULL_PATH" | grep -q "^---$"; then
    # Frontmatter exists — update the fields we care about (idempotent for re-runs)
    echo "  [info] Frontmatter already exists in ${PATH_ARG} — updating metadata fields"
    # Use sed to update specific fields
    for pair in \
        "title: ${TITLE}" \
        "persona: ${PERSONA}" \
        "created: ${DATE_ONLY}" \
        "status: ${STATUS}" \
        "tags: [${TAGS}]" \
        "freshness_days: ${FRESHNESS}" \
        "summary: ${SUMMARY}"; do
        key="${pair%%: *}"
        if grep -q "^${key}:" "$FULL_PATH"; then
            sed -i "s/^${key}:.*/${pair}/" "$FULL_PATH"
        else
            sed -i "/^---$/a\\${pair}" "$FULL_PATH"
        fi
    done
else
    # Inject frontmatter at the top of the file
    FRONTMATTER=$(cat <<FM
---
title: ${TITLE}
persona: ${PERSONA}
created: ${DATE_ONLY}
status: ${STATUS}
tags: [${TAGS}]
freshness_days: ${FRESHNESS}
summary: ${SUMMARY}
path: ${PATH_ARG}
---
FM
)
    # Prepend frontmatter before the existing content
    tmpfile=$(mktemp)
    echo "$FRONTMATTER" > "$tmpfile"
    cat "$FULL_PATH" >> "$tmpfile"
    mv "$tmpfile" "$FULL_PATH"
fi

# ── Escape pipe characters in summary for Markdown table ─────────────────────
# Replace `|` with `\|` to prevent table breakage
SUMMARY_SAFE=$(echo "$SUMMARY" | sed 's/|/\\|/g')
TITLE_SAFE=$(echo "$TITLE" | sed 's/|/\\|/g')

# ── Append to Index ──────────────────────────────────────────────────────────

ENTRY="| ${DATE_ONLY} | ${TITLE_SAFE} | ${PERSONA} | \`${STATUS}\` | \`${TAGS//,/\`, \`}\` | ${FRESHNESS} days | ${SUMMARY_SAFE} | [${PATH_ARG}](${PATH_ARG}) |"

if [ ! -f "$INDEX_FILE" ]; then
    fail 4 "Index file not found: ${INDEX_FILE}"
fi

# Find the <!-- /Index-Table --> marker and insert the new entry before it
MARKER_LINE=$(grep -n '<!-- /Index-Table -->' "$INDEX_FILE" | head -1 | cut -d: -f1)
if [ -z "$MARKER_LINE" ]; then
    fail 4 "No <!-- /Index-Table --> marker found in index file — cannot append"
fi

# Insert the new entry one line before the marker
INSERT_LINE=$((MARKER_LINE - 1))
sed -i "${INSERT_LINE}i\\${ENTRY}" "$INDEX_FILE"

# ── Success Log ──────────────────────────────────────────────────────────────

{
    echo "[${TIMESTAMP}] SUCCESS: Artifact registered"
    echo "  persona=${PERSONA}"
    echo "  title=${TITLE}"
    echo "  path=${PATH_ARG}"
    echo "  status=${STATUS}"
    echo "  index=${INDEX_FILE}"
} >> "$LOGFILE"

echo "REGISTRATION SUCCESSFUL: ${TITLE}"
echo "  Path:     ${FULL_PATH}"
echo "  Index:    ${INDEX_FILE}"
echo "  Persona:  ${PERSONA}"
echo "  Status:   ${STATUS}"
echo "  Log:      ${LOGFILE}"
exit 0
