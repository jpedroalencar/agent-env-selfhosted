#!/usr/bin/env bash
#===============================================================================
# reuse-artifact.sh
#
# Reuse Decision Framework — evaluates whether an existing vault artifact
# can be reused for a new query, or whether fresh research is required.
#
# Takes a lookup result (from lookup-artifact.sh), the artifact content,
# and the current request context, and produces a structured decision with
# citation stub if reuse is recommended.
#
# Designed to be called BY persona agents as part of the retrieval workflow:
#   1. lookup-artifact.sh — find matching artifacts
#   2. freshness-check.sh — evaluate staleness
#   3. reuse-artifact.sh — decide: reuse or research
#
# Usage:
#   ./scripts/reuse-artifact.sh --artifact-path "<path>" --request "What I need"
#   ./scripts/reuse-artifact.sh --artifact-path "<path>" --request "..." --force-reuse
#   ./scripts/reuse-artifact.sh --artifact-path "<path>" --request "..." --json
#
# Options:
#   --artifact-path <path>  Path to the artifact file (required)
#   --request <text>        The user's original request for context matching (required)
#   --force-reuse           Skip coverage evaluation and force reuse decision
#   --json                  Output in machine-readable JSON format
#
# Output:
#   Decision + citation stub in the format agents should use to cite the artifact.
#
# Exit codes:
#   0 — Reuse recommended
#   1 — Fresh research recommended (artifact partially covers or doesn't match)
#   2 — Error (bad args, missing file, etc.)
#===============================================================================

set -euo pipefail

# ── Auto-detect repo root ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${GIT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
INDEX_FILE="${ARTIFACTS_INDEX:-${REPO_ROOT}/artifacts/index.md}"

ARTIFACT_PATH=""
REQUEST_TEXT=""
FORCE_REUSE=false
JSON_OUTPUT=false
TODAY=$(date '+%Y-%m-%d')
TODAY_EPOCH=$(date '+%s')

# ── Arg Parsing ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --artifact-path)  ARTIFACT_PATH="$2"; shift 2 ;;
        --request)        REQUEST_TEXT="$2";  shift 2 ;;
        --force-reuse)    FORCE_REUSE=true;    shift ;;
        --json)           JSON_OUTPUT=true;    shift ;;
        *)  echo "ERROR: Unknown option: $1" >&2
            echo "Usage: $0 --artifact-path <path> --request \"<request>\" [--force-reuse] [--json]" >&2
            exit 2 ;;
    esac
done

if [ -z "$ARTIFACT_PATH" ]; then echo "ERROR: --artifact-path is required" >&2; exit 2; fi
if [ -z "$REQUEST_TEXT" ]; then echo "ERROR: --request is required" >&2; exit 2; fi

# Resolve full path
if [ "${ARTIFACT_PATH:0:1}" = "/" ]; then
    FULL_PATH="$ARTIFACT_PATH"
else
    FULL_PATH="${REPO_ROOT}/${ARTIFACT_PATH}"
fi

if [ ! -f "$FULL_PATH" ]; then
    echo "ERROR: Artifact file not found: ${FULL_PATH}" >&2
    exit 2
fi

# ── Extract frontmatter from artifact ────────────────────────────────────────
extract_frontmatter() {
    local file="$1"
    local field="$2"
    awk -v f="$field" '
        /^---$/ { count++; next }
        count == 1 && $0 ~ "^"f":" {
            sub(/^[^:]+:[[:space:]]*/, "")
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            print
            exit
        }
        count == 2 { exit }
    ' "$file"
}

TITLE=$(extract_frontmatter "$FULL_PATH" "title")
PERSONA=$(extract_frontmatter "$FULL_PATH" "persona")
CREATED=$(extract_frontmatter "$FULL_PATH" "created")
STATUS=$(extract_frontmatter "$FULL_PATH" "status")
TAGS=$(extract_frontmatter "$FULL_PATH" "tags" | sed 's/\[//; s/\]//; s/,//g')
FRESHNESS_DAYS=$(extract_frontmatter "$FULL_PATH" "freshness_days")
SUMMARY=$(extract_frontmatter "$FULL_PATH" "summary")

# Fall back to filename-derived title if frontmatter parsing fails
if [ -z "$TITLE" ]; then
    TITLE=$(basename "$FULL_PATH" .md | sed 's/^[0-9-]*_//' | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')
fi

# ── Compute freshness ──────────────────────────────────────────────────────────
AGE_DAYS=9999
FRESH=true
if [ -n "$CREATED" ] && [ -n "$FRESHNESS_DAYS" ]; then
    CREATED_EPOCH=$(date -d "$CREATED" '+%s' 2>/dev/null || echo 0)
    if [ "$CREATED_EPOCH" -gt 0 ]; then
        AGE_DAYS=$(( (TODAY_EPOCH - CREATED_EPOCH) / 86400 ))
        if [ "$AGE_DAYS" -gt "$FRESHNESS_DAYS" ]; then
            FRESH=false
        fi
    fi
fi

# ── Compute coverage score ────────────────────────────────────────────────────
# Simple keyword overlap between request and artifact metadata

# Normalize for matching
REQ_LOWER=$(echo "$REQUEST_TEXT" | tr '[:upper:]' '[:lower:]')
TITLE_LOWER=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]')
SUMMARY_LOWER=$(echo "$SUMMARY" | tr '[:upper:]' '[:lower:]')
TAGS_LOWER=$(echo "$TAGS" | tr '[:upper:]' '[:lower:]')

# Extract key terms from request (words 3+ chars, not stop words)
STOP_WORDS="the a an is in on at to for of and or with from by this that these those what when where how which who"
REQ_TERMS=""
for word in $REQ_LOWER; do
    word=$(echo "$word" | sed 's/[^a-z0-9]//g')
    [ ${#word} -lt 3 ] && continue
    skip=false
    for sw in $STOP_WORDS; do
        [ "$word" = "$sw" ] && skip=true && break
    done
    $skip && continue
    REQ_TERMS="$REQ_TERMS $word"
done

# Count matches across title, summary, tags, and content
MATCH_COUNT=0
TERM_COUNT=0
COVERED_TERMS=""
MISSED_TERMS=""

for term in $REQ_TERMS; do
    TERM_COUNT=$((TERM_COUNT + 1))
    matched=false
    if echo "$TITLE_LOWER" | grep -q "$term"; then matched=true; fi
    if echo "$SUMMARY_LOWER" | grep -q "$term"; then matched=true; fi
    if echo "$TAGS_LOWER" | grep -q "$term"; then matched=true; fi
    
    if [ "$matched" = true ]; then
        MATCH_COUNT=$((MATCH_COUNT + 1))
        COVERED_TERMS="$COVERED_TERMS $term"
    else
        MISSED_TERMS="$MISSED_TERMS $term"
    fi
done

COVERAGE_PCT=0
if [ "$TERM_COUNT" -gt 0 ]; then
    COVERAGE_PCT=$(( (MATCH_COUNT * 100) / TERM_COUNT ))
fi

# ── Decision Logic ─────────────────────────────────────────────────────────────

DECISION="research"
DECISION_REASON=""

if [ "$FORCE_REUSE" = true ]; then
    DECISION="reuse"
    DECISION_REASON="Force-reuse flag set"
elif [ "$TERM_COUNT" -eq 0 ]; then
    # Could not extract terms from request — default to reuse if fresh
    if [ "$FRESH" = true ]; then
        DECISION="reuse_with_caution"
        DECISION_REASON="Could not evaluate request-artifact coverage; artifact is fresh. Use with caution."
    else
        DECISION="research"
        DECISION_REASON="Could not evaluate coverage and artifact is stale."
    fi
elif [ "$COVERAGE_PCT" -ge 50 ] && [ "$FRESH" = true ]; then
    DECISION="reuse"
    DECISION_REASON="Strong coverage (${COVERAGE_PCT}%) and artifact is fresh"
elif [ "$COVERAGE_PCT" -ge 30 ] && [ "$FRESH" = true ]; then
    DECISION="reuse_with_supplement"
    DECISION_REASON="Partial coverage (${COVERAGE_PCT}%) — reuse and supplement with targeted research on:${MISSED_TERMS}"
elif [ "$COVERAGE_PCT" -ge 50 ] && [ "$FRESH" = false ]; then
    DECISION="refresh"
    DECISION_REASON="Good coverage (${COVERAGE_PCT}%) but artifact is stale (${AGE_DAYS}d old, threshold ${FRESHNESS_DAYS}d). Recommend refresh."
elif [ "$COVERAGE_PCT" -lt 30 ]; then
    DECISION="research"
    DECISION_REASON="Insufficient coverage (${COVERAGE_PCT}%) between request and artifact"
else
    DECISION="research"
    DECISION_REASON="Unknown — defaulting to fresh research"
fi

# ── Build citation stub ────────────────────────────────────────────────────────
CITATION_STUB="[Knowledge Vault — ${TITLE}]
  Path: ${ARTIFACT_PATH}
  Persona: ${PERSONA:-unknown}  |  Date: ${CREATED:-unknown}
  Freshness: ${AGE_DAYS}d old / ${FRESHNESS_DAYS:-?}d threshold ($([ "$FRESH" = true ] && echo "Fresh ✅" || echo "Stale ⚠️"))
  Summary: ${SUMMARY:-No summary available}"

REUSE_TEMPLATE="[Knowledge Vault — Artifact Reused]
  Title: ${TITLE}
  Path: ${ARTIFACT_PATH}
  Persona: ${PERSONA:-unknown}  |  Date: ${CREATED:-unknown}
  Freshness: ${AGE_DAYS}/${FRESHNESS_DAYS:-?} days ($([ "$FRESH" = true ] && echo 'fresh' || echo 'stale'))
  Coverage: ${COVERAGE_PCT}% (${MATCH_COUNT}/${TERM_COUNT} request terms matched)
  Summary: ${SUMMARY:-No summary available}"

# ── Output ─────────────────────────────────────────────────────────────────────

if [ "$JSON_OUTPUT" = true ]; then
    cat <<JSON
{
  "decision": "${DECISION}",
  "decision_reason": "${DECISION_REASON}",
  "artifact": {
    "title": "${TITLE}",
    "path": "${ARTIFACT_PATH}",
    "persona": "${PERSONA}",
    "created": "${CREATED}",
    "status": "${STATUS}",
    "tags": "${TAGS}",
    "freshness_days": ${FRESHNESS_DAYS:-0},
    "age_days": ${AGE_DAYS},
    "fresh": ${FRESH}
  },
  "coverage": {
    "request_terms": ${TERM_COUNT},
    "matched_terms": ${MATCH_COUNT},
    "coverage_pct": ${COVERAGE_PCT},
    "covered_terms": "${COVERED_TERMS}",
    "missed_terms": "${MISSED_TERMS}"
  }
}
JSON
else
    echo "━━━ Reuse Decision Framework ━━━"
    echo "Request: ${REQUEST_TEXT}"
    echo "Artifact: ${TITLE} (${PERSONA:-?})"
    echo ""
    echo "Decision: ${DECISION}"
    echo "Reason: ${DECISION_REASON}"
    echo ""
    echo "Coverage: ${COVERAGE_PCT}% (${MATCH_COUNT}/${TERM_COUNT} terms matched)"
    if [ -n "$MISSED_TERMS" ]; then
        echo "Uncovered terms:${MISSED_TERMS}"
    fi
    echo "Freshness: ${AGE_DAYS}d old / ${FRESHNESS_DAYS:-?}d threshold"
    echo ""
    
    case "$DECISION" in
        reuse)
            echo "→ REUSE RECOMMENDED"
            echo ""
            echo "${REUSE_TEMPLATE}"
            ;;
        reuse_with_caution)
            echo "→ REUSE WITH CAUTION"
            echo ""
            echo "${REUSE_TEMPLATE}"
            echo ""
            echo "Note: ${DECISION_REASON}"
            ;;
        reuse_with_supplement)
            echo "→ REUSE + SUPPLEMENT"
            echo ""
            echo "${REUSE_TEMPLATE}"
            echo ""
            echo "Supplemental research needed on:${MISSED_TERMS}"
            ;;
        refresh)
            echo "→ REFRESH RECOMMENDED"
            echo ""
            echo "${CITATION_STUB}"
            echo ""
            echo "Artifact has good coverage but is stale. Perform refresh."
            ;;
        research)
            echo "→ FRESH RESEARCH RECOMMENDED"
            echo ""
            echo "${CITATION_STUB}"
            echo ""
            echo "${DECISION_REASON}"
            ;;
    esac
fi

# Exit code based on decision
case "$DECISION" in
    reuse|reuse_with_caution) exit 0 ;;
    reuse_with_supplement)    exit 0 ;;
    refresh)                  exit 0 ;;
    research)                 exit 1 ;;
esac
