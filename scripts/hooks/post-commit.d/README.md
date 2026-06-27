# Post-Commit Hooks

Drop executable scripts here. They run in alphabetical order after every
successful commit. Failures are reported but do not roll back the commit.

## Contract

- Receives no arguments
- Working directory is the repo root
- Exit 0 = pass. Exit non-zero = warning only

## Scope

These hooks enforce Platform repository policy — rules that apply to
every commit regardless of which tool created it. None depend on Hermes.

## Planned hooks

| Hook | Purpose |
|------|---------|
| `01-auto-push` | Push to origin if on main branch |
| `02-release-notes` | Generate or update release notes from commit messages |
