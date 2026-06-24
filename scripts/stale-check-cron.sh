#!/usr/bin/env bash
#===============================================================================
# stale-check-cron.sh
#
# Cron-based stale artifact checker for the Knowledge Vault.
# Designed to be run as a scheduled cron job to proactively detect stale
# artifacts and report them.
#
# This script does NOT modify any artifacts — it only detects and reports.
# Stale artifacts should be refreshed manually or via the refresh workflow.
#
# Usage:
#   ./scripts/stale-check-cron.sh                        # Full report
#   ./scripts/stale-check-cron.sh --summary-only          # Brief summary
#   ./scripts/stale-check-cron.sh --notify                # Produce machine-readable alert
#   ./scripts/stale-check-cron.sh --warn-days 14          # Warn 14 days before stale
#   ./scripts/stale-check-cron.sh --cron-report           # Cron-optimized output
#
# Options:
#   --summary-only   Brief output (for quiet cron jobs)
#   --notify         Markdown-formatted alert for notification delivery
#   --warn-days <n>  Days before staleness to warn (default: 7)
#   --cron-report    Minimal output optimized for cron delivery (no decoration)
#
# Exit codes:
#   0 — No stale artifacts found
#   1 — At least one stale or warning-level artifact found
#
# Environment:
#   REPO_ROOT   — Override repo root (default: auto-detect)
#   LOG_DIR     — Override log directory (default: .hermes/vault-logs)
#===============================================================================

set -euo pipefail

# ── Auto-detect ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${GIT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
INDEX_FILE="${REPO_ROOT}/artifacts/index.md"
LOG_DIR="${LOG_DIR:-${REPO_ROOT}/.hermes/vault-logs}"
mkdir -p "$LOG_DIR"

SUMMARY_ONLY=false
NOTIFY=false
CRON_REPORT=false
WARN_DAYS=7
TODAY=$(date '+%Y-%m-%d')
TODAY_EPOCH=$(date '+%s')

while [[ $# -gt 0 ]]; do
    case "$1" in
        --summary-only)  SUMMARY_ONLY=true;  shift ;;
        --notify)        NOTIFY=true;        shift ;;
        --cron-report)   CRON_REPORT=true;   shift ;;
        --warn-days)     WARN_DAYS="$2";     shift 2 ;;
        *) echo "ERROR: Unknown option: $1" >&2; exit 2 ;;
    esac
done

if [ ! -f "$INDEX_FILE" ]; then
    echo "ERROR: Index file not found: ${INDEX_FILE}" >&2
    exit 2
fi

# ── Helper ──────────────────────────────────────────────────────────────────────
age_days() {
    local created_date="$1"
    local created_epoch
    created_epoch=$(date -d "$created_date" '+%s' 2>/dev/null || echo 0)
    [ "$created_epoch" -eq 0 ] && { echo "9999"; return; }
    echo $(( (TODAY_EPOCH - created_epoch) / 86400 ))
}

# ── Parse Index ─────────────────────────────────────────────────────────────────
declare -a STALE_LIST=()
declare -a WARN_LIST=()

STALE_COUNT=0
WARN_COUNT=0
TOTAL=0

while IFS= read -r line; do
    # Stop at the /Index-Table marker
    if echo "$line" | grep -q '<!-- /Index-Table -->'; then break; fi
    
    # Skip non-table lines
    if ! echo "$line" | grep -qE '^[[:space:]]*\|'; then continue; fi
    # Skip header and separator lines
    if echo "$line" | grep -qE '^[[:space:]]*\|[[:space:]]*(Date|---|$)' ; then continue; fi
    
    raw=$(echo "$line" | sed 's/^[[:space:]]*|[[:space:]]*//; s/[[:space:]]*|[[:space:]]*$//')
    date_val=$(echo "$raw" | cut -d'|' -f1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    title_val=$(echo "$raw" | cut -d'|' -f2 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    persona_val=$(echo "$raw" | cut -d'|' -f3 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    status_val=$(echo "$raw" | cut -d'|' -f4 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    freshness_val=$(echo "$raw" | cut -d'|' -f6 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed 's/ days//')
    
    [ -z "$date_val" ] && continue
    [ -z "$title_val" ] && continue
    [ -z "$freshness_val" ] && continue
    
    TOTAL=$((TOTAL + 1))
    age=$(age_days "$date_val")
    
    if [ "$age" -gt "$freshness_val" ]; then
        STALE_COUNT=$((STALE_COUNT + 1))
        STALE_LIST+=("${date_val}|${title_val}|${persona_val}|${status_val}|${freshness_val}|${age}")
    elif [ $((freshness_val - age)) -le "$WARN_DAYS" ]; then
        WARN_COUNT=$((WARN_COUNT + 1))
        WARN_LIST+=("${date_val}|${title_val}|${persona_val}|${status_val}|${freshness_val}|${age}")
    fi
done < "$INDEX_FILE"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S UTC')
LOGFILE="${LOG_DIR}/stale-check-$(date '+%Y%m%d%H%M%S').log"

# ── Log ─────────────────────────────────────────────────────────────────────────
{
    echo "[${TIMESTAMP}] STALE CHECK"
    echo "  total=${TOTAL} stale=${STALE_COUNT} warn=${WARN_COUNT} warn_days=${WARN_DAYS}"
    echo "  STALE:"
    for item in "${STALE_LIST[@]}"; do
        echo "    - $(echo "$item" | cut -d'|' -f2) ($(echo "$item" | cut -d'|' -f3))"
    done
    echo "  WARNING:"
    for item in "${WARN_LIST[@]}"; do
        echo "    - $(echo "$item" | cut -d'|' -f2) ($(echo "$item" | cut -d'|' -f3))"
    done
} >> "$LOGFILE"

# ── Output ──────────────────────────────────────────────────────────────────────

if [ "$CRON_REPORT" = true ]; then
    # Minimal cron output
    if [ "$STALE_COUNT" -eq 0 ] && [ "$WARN_COUNT" -eq 0 ]; then
        echo "✅ No stale artifacts"
        exit 0
    fi
    echo "⚠️  ${STALE_COUNT} stale, ${WARN_COUNT} approaching stale"
    for item in "${STALE_LIST[@]}"; do
        t=$(echo "$item" | cut -d'|' -f2)
        a=$(echo "$item" | cut -d'|' -f6)
        echo "  STALE: ${t} (${a}d old)"
    done
    for item in "${WARN_LIST[@]}"; do
        t=$(echo "$item" | cut -d'|' -f2)
        a=$(echo "$item" | cut -d'|' -f6)
        f=$(echo "$item" | cut -d'|' -f5)
        echo "  WARN:  ${t} (${a}d old, expires in $((f - a))d)"
    done
    exit 1
    
elif [ "$NOTIFY" = true ]; then
    # Markdown notification format
    HAS_ISSUE=false
    if [ "$STALE_COUNT" -gt 0 ] || [ "$WARN_COUNT" -gt 0 ]; then
        HAS_ISSUE=true
    fi
    
    if [ "$HAS_ISSUE" = false ]; then
        echo "**Knowledge Vault** ✅ All ${TOTAL} artifacts are fresh."
        exit 0
    fi
    
    echo "## Knowledge Vault — Stale Check Results"
    echo ""
    echo "**Date:** ${TODAY}  |  **Total Artifacts:** ${TOTAL}"
    echo ""
    if [ "$STALE_COUNT" -gt 0 ]; then
        echo "### ⚠️ Stale Artifacts (${STALE_COUNT})"
        echo ""
        for item in "${STALE_LIST[@]}"; do
            t=$(echo "$item" | cut -d'|' -f2)
            p=$(echo "$item" | cut -d'|' -f3)
            a=$(echo "$item" | cut -d'|' -f6)
            f=$(echo "$item" | cut -d'|' -f5)
            echo "- **${t}** (${p}) — ${a}d old, threshold ${f}d"
        done
        echo ""
    fi
    if [ "$WARN_COUNT" -gt 0 ]; then
        echo "### ⚡ Approaching Stale (${WARN_COUNT})"
        echo ""
        for item in "${WARN_LIST[@]}"; do
            t=$(echo "$item" | cut -d'|' -f2)
            p=$(echo "$item" | cut -d'|' -f3)
            a=$(echo "$item" | cut -d'|' -f6)
            f=$(echo "$item" | cut -d'|' -f5)
            remaining=$((f - a))
            echo "- **${t}** (${p}) — expires in ${remaining}d"
        done
        echo ""
    fi
    echo "---"
    echo "_Check logged to: ${LOGFILE}_"
    exit 1
    
elif [ "$SUMMARY_ONLY" = true ]; then
    echo "Knowledge Vault Stale Check — ${TODAY}"
    echo "  Total: ${TOTAL}  |  Stale: ${STALE_COUNT}  |  Warning: ${WARN_COUNT}  |  Fresh: $((TOTAL - STALE_COUNT - WARN_COUNT))"
    [ "$STALE_COUNT" -gt 0 ] && echo "  Run: ./scripts/lookup-artifact.sh --list-stale"
    [ "$STALE_COUNT" -gt 0 ] && exit 1
    exit 0
    
else
    # Default: full human-readable report
    echo "━━━ Knowledge Vault — Stale Artifact Check ━━━"
    echo "Date: ${TODAY}"
    echo ""
    
    if [ "$STALE_COUNT" -eq 0 ] && [ "$WARN_COUNT" -eq 0 ]; then
        echo "✅ All ${TOTAL} artifacts are fresh. No stale or warning artifacts found."
    else
        if [ "$STALE_COUNT" -gt 0 ]; then
            echo "⚠️  STALE ARTIFACTS (${STALE_COUNT})"
            echo "────────────────────────────────"
            for item in "${STALE_LIST[@]}"; do
                t=$(echo "$item" | cut -d'|' -f2)
                p=$(echo "$item" | cut -d'|' -f3)
                d=$(echo "$item" | cut -d'|' -f1)
                a=$(echo "$item" | cut -d'|' -f6)
                f=$(echo "$item" | cut -d'|' -f5)
                echo "  • ${t} (${p}) — ${a}d old, created ${d}, threshold ${f}d"
            done
            echo ""
        fi
        
        if [ "$WARN_COUNT" -gt 0 ]; then
            echo "⚡ APPROACHING STALE (${WARN_COUNT}) — within ${WARN_DAYS} days"
            echo "───────────────────────────────────────────────────────"
            for item in "${WARN_LIST[@]}"; do
                t=$(echo "$item" | cut -d'|' -f2)
                p=$(echo "$item" | cut -d'|' -f3)
                a=$(echo "$item" | cut -d'|' -f6)
                f=$(echo "$item" | cut -d'|' -f5)
                echo "  • ${t} (${p}) — ${a}d old, expires in $((f - a))d"
            done
            echo ""
        fi
        
        echo "━━━ Summary ━━━"
        echo "  Total:      ${TOTAL}"
        echo "  Stale:      ${STALE_COUNT}"
        echo "  Warning:    ${WARN_COUNT}"
        echo "  Fresh:      $((TOTAL - STALE_COUNT - WARN_COUNT))"
    fi
    
    echo ""
    echo "Log: ${LOGFILE}"
    
    [ "$STALE_COUNT" -gt 0 ] && exit 1
    exit 0
fi
