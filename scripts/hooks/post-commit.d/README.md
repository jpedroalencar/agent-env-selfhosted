# Post-Commit Hooks

Drop executable scripts here. They run in alphabetical order after every
successful commit. Failures are reported but do not undo the commit.

## Hook contract

- Receives no arguments
- Working directory is the repo root
- Exit 0 = pass. Exit non-zero = warning only (commit is not rolled back)

## Planned hooks

| Hook | Purpose | Phase |
|------|---------|-------|
| `01-verify-message-format` | Check commit message against policy | Future |
| `02-auto-push` | Push to origin if on main | Future |
