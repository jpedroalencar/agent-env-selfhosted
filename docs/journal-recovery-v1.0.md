# Engineering Journal Recovery Procedure – v1.0

**Target file:** `log/build-log.md`

## Scope
- Verify the journal exists.
- Ensure it is intact and append‑only.
- Record a recovery artifact **only if a recovery was required**.
- No architecture changes or contract modifications.

## Steps
1. **Existence check** – Fail if the journal is missing:
   ```bash
   test -f log/build-log.md || { echo "ERROR: missing journal"; exit 1; }
   ```
2. **Append‑only guard verification** – Run the pre‑commit hook; it exits non‑zero on any illegal modification:
   ```bash
   scripts/hooks/pre-commit.d/07-build-log-append-only || { echo "ERROR: append‑only guard failed"; exit 1; }
   ```
3. **Create recovery artifact *only when a problem was detected***:
   ```bash
   if [ $? -ne 0 ]; then
       cat <<EOF > artifacts/operations-manager/host-validation/journal-recovery-v1.0-$(date +%Y%m%d).md
   # Journal Recovery – v1.0
   * Date: $(date -u)
   * Issue: $(test -f log/build-log.md || echo "missing journal")$(git diff --cached log/build-log.md | grep '^-' | wc -l | awk '{if($1>0)print ", illegal modification"}')
   * Action: Verified existence and append‑only protection of `log/build-log.md`.
   EOF
   else
       echo "Journal intact – no recovery artifact needed."
   fi
   ```
4. **Commit the artifact** (if created) with a clear message; the journal itself remains unchanged.

All steps are operational, and the artifact is produced **only when a recovery action took place**.

**Target file:** `log/build-log.md`

## Scope
- Verify the journal exists.
- Ensure it is intact and append‑only.
- Record a recovery artifact **only if a recovery was required**.
- No architecture changes or contract modifications.

## Steps
1. **Existence check** – Fail if the journal is missing:
   ```bash
   test -f log/build-log.md || { echo "ERROR: missing journal"; exit 1; }
   ```
2. **Append‑only guard verification** – Run the pre‑commit hook; it exits non‑zero on any illegal modification:
   ```bash
   scripts/hooks/pre-commit.d/07-build-log-append-only || { echo "ERROR: append‑only guard failed"; exit 1; }
   ```
3. **Create recovery artifact *only when a problem was detected***:
   ```bash
   if [ $? -ne 0 ]; then
       cat <<EOF > artifacts/operations-manager/host-validation/journal-recovery-v1.0-$(date +%Y%m%d).md
   # Journal Recovery – v1.0
   * Date: $(date -u)
   * Issue: $([ -f log/build-log.md ] || echo "missing journal")$(git diff --cached log/build-log.md | grep '^-' | wc -l | awk '{if($1>0)print ", illegal modification"}')
   * Action: Verified existence and append‑only protection of `log/build-log.md`.
   EOF
   else
       echo "Journal intact – no recovery artifact needed."
   fi
   ```
4. **Commit the artifact** (if created) with a clear message; the journal itself remains unchanged.

All steps are operational, and the artifact is produced **only when a recovery action took place**.
