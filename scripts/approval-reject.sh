#!/usr/bin/env bash
# ==========================================================
# approval-reject.sh — Reject a pending proposal
# ==========================================================
# Wrapper around approval_service Python module.
#
# Actions:
#   1. Write rejection reason to package
#   2. Create rejected record (JSON)
#   3. Move package directory to rejected/
#   4. Append engineering journal entry
#
# Does NOT push. Does NOT revert the local commit.
#
# Usage:
#   scripts/approval-reject.sh [PROPOSAL_ID] ["reason"]
#
# If no ID is given, rejects the most recent pending package.
# ==========================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 - "$REPO_ROOT" "$@" <<'PYEOF'
import sys, pathlib, shutil, datetime

repo = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(repo))
from approval_service import (
    PENDING_DIR, REJECTED_DIR, _create_approval_record
)

proposal_id = sys.argv[2] if len(sys.argv) > 2 else None
reason = sys.argv[3] if len(sys.argv) > 3 else "No reason specified"

# Find the pending package directory
if proposal_id:
    pkg_dir = PENDING_DIR / proposal_id
    if not pkg_dir.exists():
        print(f"ERROR: Package not found: {proposal_id}", file=sys.stderr)
        sys.exit(1)
else:
    dirs = sorted(
        [d for d in PENDING_DIR.iterdir() if d.is_dir()],
        key=lambda d: d.stat().st_mtime,
        reverse=True
    )
    if not dirs:
        print("ERROR: No pending approval packages found.", file=sys.stderr)
        sys.exit(1)
    pkg_dir = dirs[0]
    proposal_id = pkg_dir.name

print(f"[approval-reject] Package: {proposal_id}")
print(f"[approval-reject] Reason: {reason}")

# Write rejection reason to package before moving
rejection_file = pkg_dir / "rejection-reason.txt"
now = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
rejection_file.write_text(f"Rejected: {now}\nReason: {reason}\n")
print("[approval-reject] Rejection reason recorded.")

# Create rejected record via the service
rejected_path = _create_approval_record("rejected", proposal_id, {"rejection_reason": reason})
print(f"[approval-reject] Rejected record: {rejected_path.name}")

# Move package directory to rejected/
rejected_dir = REJECTED_DIR / proposal_id
rejected_dir.mkdir(parents=True, exist_ok=True)
for item in pkg_dir.iterdir():
    dest = rejected_dir / item.name
    if item.is_dir():
        shutil.copytree(item, dest, dirs_exist_ok=True)
    else:
        shutil.copy2(item, dest)
shutil.rmtree(pkg_dir)
print(f"[approval-reject] Package moved to approval/rejected/{proposal_id}/")

# Append engineering journal entry
journal = repo / "log" / "build-log.md"
if journal.exists():
    entry = f"""
---
## {now[:10]} — Approval Package Rejected: {proposal_id}

### Date
{now[:10]}

### Source
`#provenance: approval-pipeline`

### Decision
Approval package **{proposal_id}** was rejected by operator.

### Reasoning
{reason}

### Changes Made
- Package moved from `approval/pending/{proposal_id}/` to `approval/rejected/{proposal_id}/`
- Rejection reason recorded
- No push performed
- Journal entry appended

### Lessons Learned
_Review rejection reason for improvements in next sprint._

### Follow-Up Actions
- [ ] Address rejection reason and create revised proposal if needed
"""
    with open(journal, "a") as f:
        f.write(entry)
    print("[approval-reject] Journal entry appended.")

print(f"[approval-reject] REJECTED: {proposal_id}")
PYEOF
