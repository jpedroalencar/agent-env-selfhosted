#!/usr/bin/env bash
#===============================================================================
# lookup-artifact.sh
#
# Structured artifact lookup with relevance ranking and freshness evaluation.
# Designed for persona agents to call BEFORE starting new research.
#
# Searches the Knowledge Vault by keyword, persona, tag, or full-text,
# evaluates each match for relevance and staleness, and produces a ranked
# output suitable for the reuse decision framework.
#
# Usage:
#   ./scripts/lookup-artifact.sh --query "<search term>"
#   ./scripts/lookup-artifact.sh --query "deepseek" --persona research-analyst
#   ./scripts/lookup-artifact.sh --query "aapl" --freshness-only
#   ./scripts/lookup-artifact.sh --list-stale
#   ./scripts/lookup-artifact.sh --list-all
#
# Options:
#   --query <str>      Keyword or phrase to search for (required unless listing)
#   --persona <str>    Optional: limit search to a specific persona
#   --tag <str>        Optional: limit search to a specific tag match
#   --freshness-only   Only return results that are NOT stale
#   --list-all         List all registered artifacts with freshness status
#   --list-stale       List only stale artifacts
#   --json             Output as JSON (machine-readable)
#
# Output modes:
#   Default: human-readable ranked artifact list with freshness indicators
#   --json:  Machine-readable JSON for programmatic consumption
#
# Exit codes:
#   0 — Results found (or list complete)
#   1 — Invalid arguments
#   2 — No results found
#   3 — Freshness evaluation failed
#===============================================================================

set -euo pipefail

# ── Auto-detect repo root ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${GIT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
INDEX_FILE="${ARTIFACTS_INDEX:-${REPO_ROOT}/artifacts/index.md}"

# ── Arg Defaults ─────────────────────────────────────────────────────────────
QUERY=""
PERSONA=""
TAG=""
FRESHNESS_ONLY=false
LIST_ALL=false
LIST_STALE=false
JSON_OUTPUT=false
TODAY=$(date '+%Y-%m-%d')
TODAY_EPOCH=$(date '+%s')

# ── Arg Parsing ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --query)          QUERY="$2";         shift 2 ;;
        --persona)        PERSONA="$2";       shift 2 ;;
        --tag)            TAG="$2";           shift 2 ;;
        --freshness-only) FRESHNESS_ONLY=true; shift ;;
        --list-all)       LIST_ALL=true;      shift ;;
        --list-stale)     LIST_STALE=true;    shift ;;
        --json)           JSON_OUTPUT=true;   shift ;;
        *)  echo "ERROR: Unknown option: $1" >&2
            echo "Usage: $0 --query <term> [--persona <p>] [--tag <t>] [--freshness-only] [--list-all|--list-stale] [--json]" >&2
            exit 1 ;;
    esac
done

# ── Validation ───────────────────────────────────────────────────────────────
if [ "$LIST_ALL" = false ] && [ "$LIST_STALE" = false ] && [ -z "$QUERY" ]; then
    echo "ERROR: Either --query, --list-all, or --list-stale is required." >&2
    echo "Usage: $0 --query <term> [options]" >&2
    exit 1
fi

if [ ! -f "$INDEX_FILE" ]; then
    echo "ERROR: Index file not found: ${INDEX_FILE}" >&2
    exit 1
fi

# ── Helper: parse a single index table row ─────────────────────────────────────
parse_row() {
    local line="$1"
    # Index format: | date | title | persona | status | tags | freshness | summary | path |
    # Remove leading/trailing pipes and whitespace, then split on '|'
    local raw
    raw=$(echo "$line" | sed 's/^[[:space:]]*|[[:space:]]*//; s/[[:space:]]*|[[:space:]]*$//')
    
    # Parse by splitting on '|' while preserving markdown links in path
    local date_val title_val persona_val status_val tags_val freshness_val summary_val path_val
    
    date_val=$(echo "$raw" | cut -d'|' -f1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    title_val=$(echo "$raw" | cut -d'|' -f2 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    persona_val=$(echo "$raw" | cut -d'|' -f3 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    status_val=$(echo "$raw" | cut -d'|' -f4 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    tags_val=$(echo "$raw" | cut -d'|' -f5 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    freshness_val=$(echo "$raw" | cut -d'|' -f6 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed 's/ days//')
    summary_val=$(echo "$raw" | cut -d'|' -f7 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    path_val=$(echo "$raw" | cut -d'|' -f8- | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    # Extract just the markdown link text (path) from [text](url)
    path_val=$(echo "$path_val" | sed -n 's/.*\[\(.*\)\](.*)/\1/p')
    
    echo "${date_val}|||${title_val}|||${persona_val}|||${status_val}|||${tags_val}|||${freshness_val}|||${summary_val}|||${path_val}"
}

# ── Helper: compute staleness ──────────────────────────────────────────────────
is_stale() {
    local created_date="$1"
    local freshness_days="$2"
    
    local created_epoch
    created_epoch=$(date -d "$created_date" '+%s' 2>/dev/null || echo 0)
    
    if [ "$created_epoch" -eq 0 ]; then
        # Can't parse date — treat as stale
        return 0
    fi
    
    local age_seconds=$(( TODAY_EPOCH - created_epoch ))
    local age_days=$(( age_seconds / 86400 ))
    
    if [ "$age_days" -gt "$freshness_days" ]; then
        return 0  # stale
    else
        return 1  # fresh
    fi
}

# ── Helper: compute age in days ────────────────────────────────────────────────
age_days() {
    local created_date="$1"
    local created_epoch
    created_epoch=$(date -d "$created_date" '+%s' 2>/dev/null || echo 0)
    if [ "$created_epoch" -eq 0 ]; then
        echo "9999"
        return
    fi
    echo $(( (TODAY_EPOCH - created_epoch) / 86400 ))
}

# ── Extract data rows from index ───────────────────────────────────────────────
RESULTS=()

while IFS= read -r line; do
    # Stop at the /Index-Table marker
    if echo "$line" | grep -q '<!-- /Index-Table -->'; then break; fi
    
    # Skip non-table lines
    if ! echo "$line" | grep -qE '^[[:space:]]*\|'; then continue; fi
    # Skip header and separator lines
    if echo "$line" | grep -qE '^[[:space:]]*\|[[:space:]]*(Date|---|$)' ; then continue; fi
    
    # Parse the line fields directly (pipe-delimited markdown table)
    # Remove leading/trailing pipe+whitespace
    raw=$(echo "$line" | sed 's/^[[:space:]]*|[[:space:]]*//; s/[[:space:]]*|[[:space:]]*$//')
    
    # Extract each field by column position using '|' as separator
    date_val=$(echo "$raw" | cut -d'|' -f1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    title_val=$(echo "$raw" | cut -d'|' -f2 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    persona_val=$(echo "$raw" | cut -d'|' -f3 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    status_val=$(echo "$raw" | cut -d'|' -f4 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    tags_val=$(echo "$raw" | cut -d'|' -f5 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    freshness_val=$(echo "$raw" | cut -d'|' -f6 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed 's/ days//')
    summary_val=$(echo "$raw" | cut -d'|' -f7 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    path_val=$(echo "$raw" | cut -d'|' -f8- | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    # Extract path from markdown link [path](url)
    path_val=$(echo "$path_val" | sed -n 's/.*\[\(.*\)\](.*)/\1/p')
    
    [ -z "$date_val" ] && continue
    [ -z "$title_val" ] && continue
    
    # Apply persona filter
    if [ -n "$PERSONA" ]; then
        if ! echo "$persona_val" | grep -qi "$PERSONA"; then
            continue
        fi
    fi
    
    # Apply tag filter
    if [ -n "$TAG" ]; then
        if ! echo "$tags_val" | grep -qi "$TAG"; then
            continue
        fi
    fi
    
    # Apply query filter
    if [ -n "$QUERY" ] && [ "$LIST_ALL" = false ] && [ "$LIST_STALE" = false ]; then
        # Search in title, summary, tags, and persona
        local_match=false
        if echo "$title_val" | grep -qi "$QUERY"; then local_match=true; fi
        if echo "$summary_val" | grep -qi "$QUERY"; then local_match=true; fi
        if echo "$tags_val" | grep -qi "$QUERY"; then local_match=true; fi
        if echo "$persona_val" | grep -qi "$QUERY"; then local_match=true; fi
        
        if [ "$local_match" = false ]; then
            continue
        fi
    fi
    
    # Compute freshness
    freshness_val=${freshness_val%% *}  # strip ' days' suffix
    stale_flag="fresh"
    if is_stale "$date_val" "$freshness_val"; then
        stale_flag="stale"
    fi
    
    age=$(age_days "$date_val")
    
    # Apply freshness filter
    if [ "$FRESHNESS_ONLY" = true ] && [ "$stale_flag" = "stale" ]; then
        continue
    fi
    
    # Apply stale filter
    if [ "$LIST_STALE" = true ] && [ "$stale_flag" = "fresh" ]; then
        continue
    fi
    
    RESULTS+=("${date_val}|${title_val}|${persona_val}|${status_val}|${tags_val}|${freshness_val}|${summary_val}|${path_val}|${age}|${stale_flag}")
done < "$INDEX_FILE"

# ── Output ─────────────────────────────────────────────────────────────────────

if [ ${#RESULTS[@]} -eq 0 ]; then
    if [ "$JSON_OUTPUT" = true ]; then
        echo '{"status":"no_results","results":[]}'
    else
        echo "No matching artifacts found."
    fi
    exit 2
fi

if [ "$JSON_OUTPUT" = true ]; then
    # JSON output
    echo '{'
    echo '  "status": "success",'
    echo '  "query": "'"${QUERY}"'",'
    echo '  "count": '"${#RESULTS[@]}"','
    echo '  "results": ['
    first=true
    for result in "${RESULTS[@]}"; do
        $first || echo ','
        first=false
        
        date_val=$(echo "$result" | cut -d'|' -f1)
        title_val=$(echo "$result" | cut -d'|' -f2)
        persona_val=$(echo "$result" | cut -d'|' -f3)
        status_val=$(echo "$result" | cut -d'|' -f4)
        tags_val=$(echo "$result" | cut -d'|' -f5)
        freshness_val=$(echo "$result" | cut -d'|' -f6)
        summary_val=$(echo "$result" | cut -d'|' -f7)
        path_val=$(echo "$result" | cut -d'|' -f8)
        age_val=$(echo "$result" | cut -d'|' -f9)
        stale_val=$(echo "$result" | cut -d'|' -f10)
        
        echo '    {'
        echo '      "date": "'"${date_val}"'",'
        echo '      "title": "'"${title_val}"'",'
        echo '      "persona": "'"${persona_val}"'",'
        echo '      "status": "'"${status_val}"'",'
        echo '      "tags": "'"${tags_val}"'",'
        echo '      "freshness_days": '"${freshness_val}"','
        echo '      "age_days": '"${age_val}"','
        echo '      "freshness": "'"${stale_val}"'",'
        echo '      "summary": "'"${summary_val}"'",'
        echo '      "path": "'"${path_val}"'"'
        echo -n '    }'
    done
    echo ''
    echo '  ]'
    echo '}'
else
    # Human-readable output
    echo "━━━ Knowledge Vault Lookup ━━━"
    echo "Query: ${QUERY:-<full listing>}"
    if [ -n "$PERSONA" ]; then echo "Persona filter: ${PERSONA}"; fi
    if [ -n "$TAG" ]; then echo "Tag filter: ${TAG}"; fi
    echo "Results: ${#RESULTS[@]}"
    echo ""
    
    for result in "${RESULTS[@]}"; do
        date_val=$(echo "$result" | cut -d'|' -f1)
        title_val=$(echo "$result" | cut -d'|' -f2)
        persona_val=$(echo "$result" | cut -d'|' -f3)
        status_val=$(echo "$result" | cut -d'|' -f4)
        tags_val=$(echo "$result" | cut -d'|' -f5)
        freshness_val=$(echo "$result" | cut -d'|' -f6)
        summary_val=$(echo "$result" | cut -d'|' -f7)
        path_val=$(echo "$result" | cut -d'|' -f8)
        age_val=$(echo "$result" | cut -d'|' -f9)
        stale_val=$(echo "$result" | cut -d'|' -f10)
        
        if [ "$stale_val" = "stale" ]; then
            icon="⚠️"
            freshness_label="STALE (${age_val}d old, threshold ${freshness_val}d)"
        else
            icon="✅"
            freshness_label="FRESH (${age_val}d old, threshold ${freshness_val}d)"
        fi
        
        echo "${icon} ${title_val}"
        echo "   Persona: ${persona_val}  |  Status: ${status_val}  |  Date: ${date_val}"
        echo "   Freshness: ${freshness_label}"
        echo "   Tags: ${tags_val}"
        echo "   Summary: ${summary_val}"
        echo "   Path: ${path_val}"
        echo ""
    done
    
    # Summary counts
    fresh_count=0
    stale_count=0
    for result in "${RESULTS[@]}"; do
        stale_val=$(echo "$result" | cut -d'|' -f10)
        if [ "$stale_val" = "stale" ]; then
            stale_count=$((stale_count + 1))
        else
            fresh_count=$((fresh_count + 1))
        fi
    done
    echo "━━━ Summary ━━━"
    echo "Fresh: ${fresh_count}  |  Stale: ${stale_count}"
fi

exit 0
