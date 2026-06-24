#!/usr/bin/env bash
#===============================================================================
# freshness-check.sh
#
# Evaluates freshness across all or targeted artifacts in the Knowledge Vault.
# Reports which artifacts are stale, which are approaching freshness thresholds,
# and overall vault freshness health.
#
# Designed for:
# - Persona agents before deciding to reuse an artifact
# - Cron-based maintenance jobs to detect staleness proactively
# - Human operators reviewing vault health
#
# Usage:
#   ./scripts/freshness-check.sh                          # Check all artifacts
#   ./scripts/freshness-check.sh --persona financial-analyst  # Check one persona
#   ./scripts/freshness-check.sh --warn-days 7            # Warn 7 days before stale
#   ./scripts/freshness-check.sh --summary-only           # Brief summary only
#   ./scripts/freshness-check.sh --json                   # Machine-readable JSON
#
# Options:
#   --persona <str>   Limit check to a specific persona
#   --warn-days <n>   Warn N days before artifact becomes stale (default: 7)
#   --summary-only    Output summary stats only, not per-artifact details
#   --json            Machine-readable JSON output
#   --exit-code       Exit 1 if any artifacts are stale (for cron alerting)
#
# Exit codes:
#   0 — All artifacts fresh (or no stale artifacts found)
#   1 — At least one artifact is stale (with --exit-code)
#   2 — Index file not found or empty
#===============================================================================

set -euo pipefail

# ── Auto-detect repo root ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${GIT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
INDEX_FILE="${ARTIFACTS_INDEX:-${REPO_ROOT}/artifacts/index.md}"
LOG_DIR="${LOG_DIR:-${REPO_ROOT}/.hermes/vault-logs}"

mkdir -p "$LOG_DIR"

TODAY=$(date '+%Y-%m-%d')
TODAY_EPOCH=$(date '+%s')
CHECK_DATE="${TODAY}"
WARN_DAYS=7
PERSONA_FILTER=""
SUMMARY_ONLY=false
JSON_OUTPUT=false
EXIT_CODE=false

# ── Arg Parsing ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --persona)     PERSONA_FILTER="$2"; shift 2 ;;
        --warn-days)   WARN_DAYS="$2";      shift 2 ;;
        --summary-only) SUMMARY_ONLY=true;  shift ;;
        --json)        JSON_OUTPUT=true;    shift ;;
        --exit-code)   EXIT_CODE=true;      shift ;;
        *)  echo "ERROR: Unknown option: $1" >&2
            echo "Usage: $0 [--persona <p>] [--warn-days <n>] [--summary-only] [--json] [--exit-code]" >&2
            exit 1 ;;
    esac
done

if [ ! -f "$INDEX_FILE" ]; then
    echo "ERROR: Index file not found: ${INDEX_FILE}" >&2
    exit 2
fi

# ── Helper: age in days ────────────────────────────────────────────────────────
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

# ── Parse index rows ───────────────────────────────────────────────────────────
declare -a ALL_ARTIFACTS=()

while IFS= read -r line; do
    # Stop at the /Index-Table marker
    if echo "$line" | grep -q '<!-- /Index-Table -->'; then break; fi
    
    # Skip non-table lines
    if ! echo "$line" | grep -qE '^[[:space:]]*\|'; then continue; fi
    # Skip header and separator lines
    if echo "$line" | grep -qE '^[[:space:]]*\|[[:space:]]*(Date|---|$)' ; then continue; fi
    
    # Parse columns
    raw=$(echo "$line" | sed 's/^[[:space:]]*|[[:space:]]*//; s/[[:space:]]*|[[:space:]]*$//')
    
    date_val=$(echo "$raw" | cut -d'|' -f1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    title_val=$(echo "$raw" | cut -d'|' -f2 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    persona_val=$(echo "$raw" | cut -d'|' -f3 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    status_val=$(echo "$raw" | cut -d'|' -f4 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    tags_val=$(echo "$raw" | cut -d'|' -f5 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    freshness_val=$(echo "$raw" | cut -d'|' -f6 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed 's/ days//')
    summary_val=$(echo "$raw" | cut -d'|' -f7 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    
    [ -z "$date_val" ] && continue
    [ -z "$title_val" ] && continue
    [ -z "$freshness_val" ] && continue
    
    # Apply persona filter
    if [ -n "$PERSONA_FILTER" ]; then
        if ! echo "$persona_val" | grep -qi "$PERSONA_FILTER"; then continue; fi
    fi
    
    age=$(age_days "$date_val")
    stale_threshold=$((freshness_val))
    
    ALL_ARTIFACTS+=("${date_val}|${title_val}|${persona_val}|${status_val}|${tags_val}|${freshness_val}|${summary_val}|${age}|${stale_threshold}")
done < "$INDEX_FILE"

# ── Compute Freshness Stats ─────────────────────────────────────────────────────

fresh_count=0
stale_count=0
warn_count=0
total=0
max_age=0
stale_list=()
warn_list=()
fresh_list=()

for artifact in "${ALL_ARTIFACTS[@]}"; do
    total=$((total + 1))
    date_val=$(echo "$artifact" | cut -d'|' -f1)
    title_val=$(echo "$artifact" | cut -d'|' -f2)
    persona_val=$(echo "$artifact" | cut -d'|' -f3)
    freshness_val=$(echo "$artifact" | cut -d'|' -f6)
    age=$(echo "$artifact" | cut -d'|' -f8)
    
    [ "$age" -gt "$max_age" ] && max_age=$age
    
    if [ "$age" -gt "$freshness_val" ]; then
        stale_count=$((stale_count + 1))
        stale_list+=("$artifact")
    elif [ $((freshness_val - age)) -le "$WARN_DAYS" ]; then
        warn_count=$((warn_count + 1))
        warn_list+=("$artifact")
    else
        fresh_count=$((fresh_count + 1))
        fresh_list+=("$artifact")
    fi
done

# ── Output ─────────────────────────────────────────────────────────────────────

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S UTC')
LOGFILE="${LOG_DIR}/freshness-$(date '+%Y%m%d%H%M%S').log"

if [ "$JSON_OUTPUT" = true ]; then
    # ── JSON Output ──
    echo '{'
    echo '  "check_date": "'"${CHECK_DATE}"'",'
    echo '  "total_artifacts": '"${total}"','
    echo '  "fresh": '"${fresh_count}"','
    echo '  "warning": '"${warn_count}"','
    echo '  "stale": '"${stale_count}"','
    echo '  "max_age_days": '"${max_age}"','
    echo '  "warn_days_threshold": '"${WARN_DAYS}"','
    echo '  "stale_artifacts": ['
    first=true
    for artifact in "${stale_list[@]}"; do
        $first || echo ','
        first=false
        title_val=$(echo "$artifact" | cut -d'|' -f2)
        persona_val=$(echo "$artifact" | cut -d'|' -f3)
        age=$(echo "$artifact" | cut -d'|' -f8)
        freshness_val=$(echo "$artifact" | cut -d'|' -f6)
        echo "    {\"title\":\"${title_val}\",\"persona\":\"${persona_val}\",\"age_days\":${age},\"threshold_days\":${freshness_val}}"
    done
    echo '  ],'
    echo '  "warning_artifacts": ['
    first=true
    for artifact in "${warn_list[@]}"; do
        $first || echo ','
        first=false
        title_val=$(echo "$artifact" | cut -d'|' -f2)
        persona_val=$(echo "$artifact" | cut -d'|' -f3)
        age=$(echo "$artifact" | cut -d'|' -f8)
        freshness_val=$(echo "$artifact" | cut -d'|' -f6)
        echo "    {\"title\":\"${title_val}\",\"persona\":\"${persona_val}\",\"age_days\":${age},\"threshold_days\":${freshness_val},\"days_until_stale\":$((freshness_val - age))}"
    done
    echo '  ]'
    echo '}'
else
    # ── Human-readable Output ──
    echo "━━━ Knowledge Vault Freshness Check ━━━"
    echo "Check date: ${CHECK_DATE}"
    echo ""
    
    if [ "$SUMMARY_ONLY" = false ]; then
        if [ ${#stale_list[@]} -gt 0 ]; then
            echo "⚠️  STALE ARTIFACTS (${stale_count})"
            echo "──────────────────────────────────"
            for artifact in "${stale_list[@]}"; do
                title_val=$(echo "$artifact" | cut -d'|' -f2)
                persona_val=$(echo "$artifact" | cut -d'|' -f3)
                date_val=$(echo "$artifact" | cut -d'|' -f1)
                age=$(echo "$artifact" | cut -d'|' -f8)
                freshness_val=$(echo "$artifact" | cut -d'|' -f6)
                echo "  • ${title_val} (${persona_val}) — ${age}d old, threshold ${freshness_val}d, created ${date_val}"
            done
            echo ""
        fi
        
        if [ ${#warn_list[@]} -gt 0 ]; then
            echo "⚡ APPROACHING STALE (${warn_count}) — within ${WARN_DAYS} days"
            echo "──────────────────────────────────────────────────────"
            for artifact in "${warn_list[@]}"; do
                title_val=$(echo "$artifact" | cut -d'|' -f2)
                persona_val=$(echo "$artifact" | cut -d'|' -f3)
                age=$(echo "$artifact" | cut -d'|' -f8)
                freshness_val=$(echo "$artifact" | cut -d'|' -f6)
                echo "  • ${title_val} (${persona_val}) — ${age}d old, expires in $((freshness_val - age))d"
            done
            echo ""
        fi
        
        if [ "$fresh_count" -gt 0 ]; then
            echo "✅ FRESH ARTIFACTS (${fresh_count})"
            if [ "$SUMMARY_ONLY" = false ]; then
                for artifact in "${fresh_list[@]}"; do
                    title_val=$(echo "$artifact" | cut -d'|' -f2)
                    persona_val=$(echo "$artifact" | cut -d'|' -f3)
                    age=$(echo "$artifact" | cut -d'|' -f8)
                    freshness_val=$(echo "$artifact" | cut -d'|' -f6)
                    echo "  • ${title_val} (${persona_val}) — ${age}d old, threshold ${freshness_val}d"
                done
            fi
            echo ""
        fi
    fi
    
    echo "━━━ Overview ━━━"
    echo "Total artifacts:  ${total}"
    echo "  ✅ Fresh:       ${fresh_count}"
    echo "  ⚡ Warning:     ${warn_count}  (within ${WARN_DAYS}d of staleness)"
    echo "  ⚠️  Stale:       ${stale_count}"
    echo "  Max age:        ${max_age}d"
    echo ""
    
    if [ "$stale_count" -gt 0 ]; then
        echo "RECOMMENDATION: Consider refreshing ${stale_count} stale artifact(s)."
        echo "  ./scripts/lookup-artifact.sh --list-stale"
    fi
    
    echo ""
    echo "Logged to: ${LOGFILE}"
fi

# ── Log results ────────────────────────────────────────────────────────────────
{
    echo "[${TIMESTAMP}] FRESHNESS CHECK"
    echo "  check_date=${CHECK_DATE}"
    echo "  total=${total} fresh=${fresh_count} warning=${warn_count} stale=${stale_count} max_age=${max_age}"
    if [ "$stale_count" -gt 0 ]; then
        echo "  STALE ARTIFACTS:"
        for artifact in "${stale_list[@]}"; do
            echo "    - $(echo "$artifact" | cut -d'|' -f2) ($(echo "$artifact" | cut -d'|' -f3))"
        done
    fi
} >> "$LOGFILE"

# ── Exit with code if requested ────────────────────────────────────────────────
if [ "$EXIT_CODE" = true ] && [ "$stale_count" -gt 0 ]; then
    exit 1
fi
exit 0
