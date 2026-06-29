'''Hermes Approval Service

Provides a stable, script‑free abstraction for the Engineering Approval
Workflow. All operations are immutable – Proposal Packages live forever in
`proposal/` and never move. Workflow state lives in JSON “Approval Records"
under `approval/`.

The service is deliberately tiny and has no external dependencies other than
the Python standard library.
'''

import pathlib
import json
import datetime
import os
import subprocess
from typing import Tuple, Optional

# ---------------------------------------------------------------------------
# Layout constants – relative to the repository root (the directory that
# contains ``agent-env-selfhosted``).  The service discovers the root by
# walking up from ``__file__`` until it finds a ``.git`` directory.
# ---------------------------------------------------------------------------

def _repo_root() -> pathlib.Path:
    # ``__file__`` points to .../agent-env-selfhosted/approval_service/__init__.py
    cur = pathlib.Path(__file__).resolve()
    # walk upward until a .git folder is found (or we hit /)
    for parent in cur.parents:
        if (parent / '.git').is_dir():
            return parent
    raise RuntimeError('Repository root not found (no .git directory)')

REPO_ROOT = _repo_root()
PROPOSAL_ROOT = REPO_ROOT / 'proposal'
APPROVAL_ROOT = REPO_ROOT / 'approval'
PENDING_DIR = APPROVAL_ROOT / 'pending'
APPROVED_DIR = APPROVAL_ROOT / 'approved'
REJECTED_DIR = APPROVAL_ROOT / 'rejected'

# Ensure directories exist on import – this is cheap and guarantees the
# layout is always present.
for _d in (PROPOSAL_ROOT, PENDING_DIR, APPROVED_DIR, REJECTED_DIR):
    _d.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _timestamp() -> str:
    return datetime.datetime.utcnow().isoformat(timespec='seconds') + 'Z'

def _next_id(prefix: str = '') -> str:
    """Generate a new monotonically‑increasing ID.

    IDs follow the pattern ``YYYY-MM-DD-NNN`` for proposals and
    ``YYYY-MM-DD-NNN_rec`` for approval records. ``prefix`` is appended after
    the ``NNN`` part (e.g. ``_rec``).
    """
    today = datetime.datetime.utcnow().strftime('%Y-%m-%d')
    n = 1
    while True:
        candidate = f"{today}-{n}{prefix}"
        # Proposals live in PROPOSAL_ROOT, records live as JSON files.
        if not (PROPOSAL_ROOT / candidate).exists() and not any(
            (p.name.startswith(candidate) for p in PENDING_DIR.iterdir())
        ) and not any(
            (p.name.startswith(candidate) for p in APPROVED_DIR.iterdir())
        ) and not any(
            (p.name.startswith(candidate) for p in REJECTED_DIR.iterdir())
        ):
            return candidate
        n += 1

def _write_json(path: pathlib.Path, data: dict) -> None:
    path.write_text(json.dumps(data, indent=2, sort_keys=True))

def _read_json(path: pathlib.Path) -> dict:
    return json.loads(path.read_text())

# ---------------------------------------------------------------------------
# Public API – used by the CLI wrapper
# ---------------------------------------------------------------------------

def generate_proposal(commit_msg: str = '') -> str:
    """Create a new immutable Proposal Package.

    Returns the proposal ID (directory name). The caller can later create a
    pending Approval Record that references this ID.
    """
    proposal_id = _next_id()
    pkg_dir = PROPOSAL_ROOT / proposal_id
    pkg_dir.mkdir()
    # Minimal required files – developers may add more later.
    (pkg_dir / 'summary.md').write_text(
        f"# Proposal Package {proposal_id}\n"
        f"Generated: {_timestamp()}\n\n"
        f"{commit_msg}\n"
    )
    (pkg_dir / 'changed-files.md').write_text('')
    (pkg_dir / 'git-diff.patch').write_text('')
    (pkg_dir / 'metadata.json').write_text(json.dumps({}, indent=2))
    return proposal_id

def _create_approval_record(state: str, proposal_id: str, extra: Optional[dict] = None) -> pathlib.Path:
    record = {
        'record_id': _next_id('_rec'),
        'proposal_id': proposal_id,
        'timestamp': _timestamp(),
        'reviewer': os.getenv('USER') or 'hermes-agent',
        'decision': state,
    }
    if extra:
        record.update(extra)
    target_dir = {
        'pending': PENDING_DIR,
        'approved': APPROVED_DIR,
        'rejected': REJECTED_DIR,
    }[state]
    path = target_dir / f"{record['record_id']}.json"
    _write_json(path, record)
    return path

def generate_pending(commit_msg: str = '') -> Tuple[str, pathlib.Path]:
    """Create a Proposal Package and a corresponding *pending* Approval Record.

    Returns ``(proposal_id, record_path)``.
    """
    proposal_id = generate_proposal(commit_msg)
    record_path = _create_approval_record('pending', proposal_id)
    return proposal_id, record_path

def _find_pending_record(proposal_id: str) -> pathlib.Path:
    for p in PENDING_DIR.iterdir():
        rec = _read_json(p)
        if rec.get('proposal_id') == proposal_id:
            return p
    raise FileNotFoundError(f'No pending approval record for proposal {proposal_id}')

def approve(proposal_id: Optional[str] = None) -> pathlib.Path:
    """Approve a pending proposal.

    * If ``proposal_id`` is omitted, the most recent pending record is used.
    * A ``git push`` is performed before the record is moved to ``approved/``.
    """
    if proposal_id is None:
        # pick the newest pending JSON file (by timestamp in filename)
        pending_files = sorted(PENDING_DIR.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True)
        if not pending_files:
            raise FileNotFoundError('No pending approval records found')
        pending_path = pending_files[0]
        rec = _read_json(pending_path)
        proposal_id = rec['proposal_id']
    else:
        pending_path = _find_pending_record(proposal_id)
    # Push – failure aborts the whole operation.
    subprocess.run(['git', 'push', 'origin', 'HEAD'], cwd=str(REPO_ROOT), check=True)
    # Create approved record
    approved_path = _create_approval_record('approved', proposal_id)
    # Delete pending record (immutability of the ledger is preserved – the
    # approved record remains as a new immutable artifact.)
    pending_path.unlink()
    return approved_path

def reject(proposal_id: Optional[str] = None, reason: str = '') -> pathlib.Path:
    """Reject a pending proposal – no git push.

    The rejection reason is stored only inside the *rejected* Approval Record.
    """
    if proposal_id is None:
        pending_files = sorted(PENDING_DIR.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True)
        if not pending_files:
            raise FileNotFoundError('No pending approval records found')
        pending_path = pending_files[0]
        rec = _read_json(pending_path)
        proposal_id = rec['proposal_id']
    else:
        pending_path = _find_pending_record(proposal_id)
    extra = {'rejection_reason': reason} if reason else None
    rejected_path = _create_approval_record('rejected', proposal_id, extra)
    pending_path.unlink()
    return rejected_path

def revise(old_proposal_id: str, revision_msg: str = '') -> Tuple[str, pathlib.Path]:
    """Create a new Proposal Package that supersedes ``old_proposal_id``.

    A new *pending* Approval Record is returned together with the new proposal
    ID.
    """
    new_proposal_id = generate_proposal(revision_msg)
    # write supersedes metadata inside the new proposal
    meta_path = PROPOSAL_ROOT / new_proposal_id / 'metadata.json'
    meta = {'supersedes': old_proposal_id}
    _write_json(meta_path, meta)
    # pending record for the new proposal
    pending_path = _create_approval_record('pending', new_proposal_id)
    return new_proposal_id, pending_path

# Helper for the CLI when the user supplies no ID – pick the most recent.
def _most_recent_pending_id() -> str:
    pending = sorted(PENDING_DIR.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True)
    if not pending:
        raise FileNotFoundError('No pending approval records')
    rec = _read_json(pending[0])
    return rec['proposal_id']

# ---------------------------------------------------------------------------
# End of service module
# ---------------------------------------------------------------------------
