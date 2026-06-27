# Pre-Commit Hooks

Drop executable scripts here. They run in alphabetical order before every commit.
Any hook that exits non-zero blocks the commit.

## Hook contract

- Receives no arguments
- Working directory is the repo root
- stdout is displayed; stderr is displayed on failure
- Exit 0 = pass. Exit non-zero = block the commit

## Planned hooks

| Hook | Purpose | Phase |
|------|---------|-------|
| `01-conventional-commits` | Validate commit message follows conventional commits format | Future |
| `02-syntax-check` | Lint staged files (shellcheck, python, yaml) | Future |
| `03-test-affected` | Run tests for changed modules | Future |
