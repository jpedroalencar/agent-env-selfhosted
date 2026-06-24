#!/usr/bin/env bash
#===============================================================================
# update-index-stats.sh
#
# Auto-computes index statistics for the Knowledge Vault.
# Replaces the static Statistics section in artifacts/index.md with
# dynamically computed values based on the current index table.
#
# This script is automatically invoked after every registration.
# It can also be run manually to refresh stats at any time.
#
# Usage:
#   ./scripts/update-index-stats.sh
#   ./scripts/update-index-stats.sh --dry-run    # Preview changes without applying
#   ./scripts/update-index-stats.sh --json       # Output stats as JSON
#
# Environment:
#   ARTIFACTS_INDEX  — Override path to the vault index
#
# Exit codes:
#   0 — Statistics updated successfully
#   1 — Index file not found
#   2 — Failed to parse index
#===============================================================================

set -eo pipefail

# ── Auto-detect repo root ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${GIT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
INDEX_FILE="${ARTIFACTS_INDEX:-${REPO_ROOT}/artifacts/index.md}"

DRY_RUN=false
JSON_OUTPUT=false
TODAY_EPOCH=$(date '+%s')

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)  DRY_RUN=true;  shift ;;
        --json)     JSON_OUTPUT=true; shift ;;
        *) echo "ERROR: Unknown option: $1" >&2; exit 2 ;;
    esac
done

if [ ! -f "$INDEX_FILE" ]; then
    echo "ERROR: Index file not found: ${INDEX_FILE}" >&2
    exit 1
fi

# ── Parse the index table ───────────────────────────────────────────────────────

declare -a DATES=()
declare -a TITLES=()
declare -a PERSONAS=()
declare -a STATUSES=()
declare -a TAGS=()
declare -a FRESHNESS=()
declare -a SUMMARIES=()
declare -a PATHS=()

TOTAL=0

while IFS= read -r line; do
    # Stop at the /Index-Table marker
    if echo "$line" | grep -q '<!-- /Index-Table -->'; then break; fi
    
    # Skip non-table lines, headers, separators
    if ! echo "$line" | grep -qE '^[[:space:]]*\|'; then continue; fi
    if echo "$line" | grep -qE '^[[:space:]]*\|[[:space:]]*(Date|---|$)' ; then continue; fi
    
    raw=$(echo "$line" | sed 's/^[[:space:]]*|[[:space:]]*//; s/[[:space:]]*|[[:space:]]*$//')
    
    date_val=$(echo "$raw" | cut -d'|' -f1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    title_val=$(echo "$raw" | cut -d'|' -f2 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    persona_val=$(echo "$raw" | cut -d'|' -f3 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    status_val=$(echo "$raw" | cut -d'|' -f4 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    tags_val=$(echo "$raw" | cut -d'|' -f5 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    freshness_val=$(echo "$raw" | cut -d'|' -f6 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed 's/ days//')
    summary_val=$(echo "$raw" | cut -d'|' -f7 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    path_val=$(echo "$raw" | cut -d'|' -f8- | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    path_val=$(echo "$path_val" | sed -n 's/.*\[\(.*\)\](.*)/\1/p')
    
    [ -z "$date_val" ] && continue
    [ -z "$title_val" ] && continue
    
    DATES+=("$date_val")
    TITLES+=("$title_val")
    PERSONAS+=("$persona_val")
    STATUSES+=("$status_val")
    TAGS+=("$tags_val")
    FRESHNESS+=("$freshness_val")
    SUMMARIES+=("$summary_val")
    PATHS+=("$path_val")
    TOTAL=$((TOTAL + 1))
done < "$INDEX_FILE"

if [ "$TOTAL" -eq 0 ]; then
    echo "ERROR: No artifacts found in index." >&2
    exit 2
fi

# ── Compute Statistics ──────────────────────────────────────────────────────────

declare -A PERSONA_COUNTS
declare -A STATUS_COUNTS
declare -A TAG_COUNTS
STALE_COUNT=0
FRESH_COUNT=0
TOTAL_FRESHNESS=0
NEWEST_DATE="0000-00-00"
OLDEST_DATE="9999-99-99"

for i in $(seq 0 $((TOTAL - 1))); do
    p="${PERSONAS[$i]}"
    s="${STATUSES[$i]}"
    t="${TAGS[$i]}"
    d="${DATES[$i]}"
    f="${FRESHNESS[$i]}"
    
    # Strip backtick markers from status
    s=$(echo "$s" | sed 's/`//g')
    
    # Skip entries with empty persona or status
    [ -n "$p" ] || continue
    [ -n "$s" ] || continue
    
    # Initialize counters with default if not yet set
    [ -z "${PERSONA_COUNTS[$p]:-}" ] && PERSONA_COUNTS["$p"]=0
    [ -z "${STATUS_COUNTS[$s]:-}" ] && STATUS_COUNTS["$s"]=0
    PERSONA_COUNTS["$p"]=$((PERSONA_COUNTS["$p"] + 1))
    STATUS_COUNTS["$s"]=$((STATUS_COUNTS["$s"] + 1))
    
    # Count tags (split by comma)
    IFS=',' read -ra TAG_ARR <<< "$(echo "$t" | sed 's/`//g')"
    for tag in "${TAG_ARR[@]}"; do
        tag=$(echo "$tag" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        if [ -n "$tag" ]; then
            [ -z "${TAG_COUNTS[$tag]:-}" ] && TAG_COUNTS["$tag"]=0
            TAG_COUNTS["$tag"]=$((TAG_COUNTS["$tag"] + 1))
        fi
    done
    
    # Date tracking
    if [[ "$d" > "$NEWEST_DATE" ]]; then NEWEST_DATE="$d"; fi
    if [[ "$d" < "$OLDEST_DATE" ]]; then OLDEST_DATE="$d"; fi
    
    # Freshness evaluation
    [ -z "$f" ] && f=0
    created_epoch=$(date -d "$d" '+%s' 2>/dev/null || echo 0)
    if [ "$created_epoch" -gt 0 ] && [ "$f" -gt 0 ]; then
        age=$(( (TODAY_EPOCH - created_epoch) / 86400 ))
        if [ "$age" -gt "$f" ]; then
            STALE_COUNT=$((STALE_COUNT + 1))
        else
            FRESH_COUNT=$((FRESH_COUNT + 1))
        fi
        TOTAL_FRESHNESS=$((TOTAL_FRESHNESS + f))
    fi
done

AVG_FRESHNESS=0
[ "$TOTAL" -gt 0 ] && AVG_FRESHNESS=$((TOTAL_FRESHNESS / TOTAL))

# Compute most tagged
MOST_TAGGED_NAME=""
MOST_TAGGED_COUNT=0
for tag in "${!TAG_COUNTS[@]}"; do
    if [ "${TAG_COUNTS[$tag]}" -gt "$MOST_TAGGED_COUNT" ]; then
        MOST_TAGGED_COUNT="${TAG_COUNTS[$tag]}"
        MOST_TAGGED_NAME="$tag"
    fi
done

# ── Build Statistics Section ────────────────────────────────────────────────────
STATS_SECTION=$(cat <<STATS

## Statistics

| Metric | Value |
|--------|-------|
| Total artifacts | ${TOTAL} |
| Last artifact | ${NEWEST_DATE} |
| Oldest artifact | ${OLDEST_DATE} |
| Fresh artifacts | ${FRESH_COUNT} |
| Stale artifacts | ${STALE_COUNT} |
| Avg freshness threshold | ${AVG_FRESHNESS} days |
| Most used tag | \`${MOST_TAGGED_NAME}\` (${MOST_TAGGED_COUNT}) |
| Unique personas | ${#PERSONA_COUNTS[@]} |
| Unique tags | ${#TAG_COUNTS[@]} |

STATS
)

# Add persona breakdown
for p in research-analyst financial-analyst dev operations-manager; do
    count=${PERSONA_COUNTS[$p]:-0}
    if [ "$count" -gt 0 ]; then
        STATS_SECTION+="| ${p} artifacts | ${count} |\n"
    fi
done

# Add status breakdown
for s in draft verified; do
    count=${STATUS_COUNTS[$s]:-0}
    if [ "$count" -gt 0 ]; then
        STATS_SECTION+="| \`${s}\` artifacts | ${count} |\n"
    fi
done

STATS_SECTION+="\n---\n"

# ── JSON Output (dry-run / info only) ──────────────────────────────────────────
if [ "$JSON_OUTPUT" = true ]; then
    echo '{'
    echo '  "total": '"${TOTAL}"','
    echo '  "fresh": '"${FRESH_COUNT}"','
    echo '  "stale": '"${STALE_COUNT}"','
    echo '  "newest_date": "'"${NEWEST_DATE}"'",'
    echo '  "oldest_date": "'"${OLDEST_DATE}"'",'
    echo '  "avg_freshness_days": '"${AVG_FRESHNESS}"','
    echo '  "unique_personas": '"${#PERSONA_COUNTS[@]}"','
    echo '  "unique_tags": '"${#TAG_COUNTS[@]}"','
    echo '  "persona_counts": {'
    first=true
    for p in "${!PERSONA_COUNTS[@]}"; do
        $first || echo ','
        first=false
        echo "    \"${p}\": ${PERSONA_COUNTS[$p]}"
    done
    echo '  },'
    echo '  "status_counts": {'
    first=true
    for s in "${!STATUS_COUNTS[@]}"; do
        $first || echo ','
        first=false
        echo "    \"${s}\": ${STATUS_COUNTS[$s]}"
    done
    echo '  }'
    echo '}'
    exit 0
fi

if [ "$DRY_RUN" = true ]; then
    echo "━━━ Knowledge Vault — Stats Preview (dry-run) ━━━"
    echo -e "$STATS_SECTION"
    exit 0
fi

# ── Replace Statistics Section in Index ─────────────────────────────────────────

# Find the Statistics section boundaries
STATS_START=$(grep -n '^## Statistics' "$INDEX_FILE" | head -1 | cut -d: -f1)
STATS_END=$(grep -n '^---' "$INDEX_FILE" | awk -v start="$STATS_START" 'NR>1 && $1 > start {print $1; exit}' | cut -d: -f1)

if [ -z "$STATS_START" ]; then
    echo "ERROR: No '## Statistics' section found in index file." >&2
    exit 2
fi

if [ -z "$STATS_END" ]; then
    # Find the next section or end of file
    STATS_END=$(wc -l < "$INDEX_FILE")
fi

# Build the new file: content before stats + new stats + content after stats
{
    head -n $((STATS_START - 1)) "$INDEX_FILE"
    echo -e "$STATS_SECTION"
    tail -n +$((STATS_END + 1)) "$INDEX_FILE"
} > "${INDEX_FILE}.tmp"

mv "${INDEX_FILE}.tmp" "$INDEX_FILE"

echo "STATISTICS UPDATED: ${TOTAL} artifacts across ${#PERSONA_COUNTS[@]} personas"
echo "  Fresh: ${FRESH_COUNT}  |  Stale: ${STALE_COUNT}"
echo "  Newest: ${NEWEST_DATE}  |  Oldest: ${OLDEST_DATE}"
exit 0
