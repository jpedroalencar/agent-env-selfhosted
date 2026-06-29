# Engineering Journal Append‑Only Policy

**File:** `log/build-log.md`

The engineering journal is the canonical source of truth for build‑related notes, decisions, and sprint retrospectives. To preserve its historical integrity we enforce the following rules:

1. **Append‑Only** – Existing entries must never be modified or removed during normal development.
2. **New Entries** – All new sprint entries are appended to the **end** of the file.
3. **Corrections** – If a previous entry contains an error, a **dedicated corrective commit** must be created. The commit message should reference the original entry (e.g., `fix: correct typo in build‑log entry for 2026‑06‑23`). The corrective commit may add a new line explaining the correction; it must **not** edit or delete the original line.
4. **File Overwrite** – Any operation that would replace the entire file (e.g., `cp`, `mv`, `rm && cat >`) is prohibited for normal journal updates.
5. **Verification** – Commit hooks verify that `log/build-log.md` exists, that the change consists only of added lines, and that the file is not recreated.

These constraints are enforced by a lightweight pre‑commit hook (see `scripts/hooks/pre-commit.d/07-build-log-append-only`). The hook aborts the commit with a clear error message if a disallowed modification is detected.

> **Note:** When the journal grows large, consider splitting it into yearly logs (e.g., `log/build-log-2026.md`). This does **not** affect the current policy – each yearly log remains append‑only.
