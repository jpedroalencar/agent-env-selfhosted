#!/usr/bin/env bash
# ==========================================================
# approval-approve.sh — Approve a pending proposal
# ==========================================================
# Wrapper around approval_service Python module.
#
# Actions:
#   1. Verify package integrity
#   2. Git push to remote
#   3. Create approved record (JSON)
#   4. Move package directory to approved/
#   5. Append engineering journal entry
#
# Usage:
#   scripts/approval-approve.sh [PROPOSAL_ID]
#
# If no ID is given, approves the most recent pending package.
# ==========================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 - "$REPO_ROOT" "$@" <<'PYEOF'
import sys, pathlib, subprocess, datetime

repo = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(repo))
from approval_service import (
    approve, PENDING_DIR, APPROVED_DIR, PROPOSAL_ROOT,
    _read_json, _find_pending_record, _most_recent_pending_id,
    _timestamp
)

proposal_id = sys.argv[2] if len(sys.argv) > 2 else None

# Find the pending package directory
if proposal_id:
    pkg_dir = PENDING_DIR / proposal_id
    if not pkg_dir.exists():
        print(f"ERROR: Package not found: {proposal_id}", file=sys.stderr)
        sys.exit(1)
else:
    # Find most recent pending directory (not JSON files)
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

print(f"[approval-approve] Package: {proposal_id}")

# Verify package integrity
required_files = ["summary.md", "changed-files.md", "git-diff.patch", "proposal-link.txt"]
missing = [f for f in required_files if not (pkg_dir / f).exists()]
if missing:
    print(f"ERROR: Package is incomplete. Missing: {', '.join(missing)}", file=sys.stderr)
    sys.exit(1)
print("[approval-approve] Package verified.")

# Git push
print("[approval-approve] Pushing to remote...")
result = subprocess.run(
    ["git", "push", "origin", "HEAD"],
    cwd=str(repo), capture_output=True, text=True
)
if result.returncode != 0:
    print(f"ERROR: git push failed: {result.stderr}", file=sys.stderr)
    sys.exit(1)
print("[approval-approve] Push successful.")

# Create approved record via the service
from approval_service import _create_approval_record
approved_path = _create_approval_record("approved", proposal_id)
print(f"[approval-approve] Approved record: {approved_path.name}")

# Move package directory to approved/
approved_dir = APPROVED_DIR / proposal_id
approved_dir.mkdir(parents=True, exist_ok=True)
import shutil
for item in pkg_dir.iterdir():
    dest = approved_dir / item.name
    if item.is_dir():
        shutil.copytree(item, dest, dirs_exist_ok=True)
    else:
        shutil.copy2(item, dest)
shutil.rmtree(pkg_dir)
print(f"[approval-approve] Package moved to approval/approved/{proposal_id}/")

# Append engineering journal entry
journal = repo / "log" / "build-log.md"
if journal.exists():
    now = datetime.datetime.utcnow()
    entry = f"""
---
## {now.strftime('%Y-%m-%d')} — Approval Package Approved: {proposal_id}

### Date
{now.strftime('%Y-%m-%d')}

### Source
`#provenance: approval-pipeline`

### Decision
Approval package **{proposal_id}** was approved and pushed to remote.

### Reasoning
Human operator reviewed the proposal package and approved. Changes pushed via `git push`.

### Changes Made
- Package moved from `approval/pending/{proposal_id}/` to `approval/approved/{proposal_id}/`
- `git push` executed successfully
- Journal entry appended

### Lessons Learned
_No new lessons in this approval cycle._

### Follow-Up Actions
None at this time.
"""
    with open(journal, "a") as f:
        f.write(entry)
    print("[approval-approve] Journal entry appended.")

print(f"[approval-approve] APPROVED: {proposal_id}")
PYEOF
