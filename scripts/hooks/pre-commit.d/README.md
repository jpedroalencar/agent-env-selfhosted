# Pre-Commit Hooks

Drop executable scripts here. They run in alphabetical order before every commit.
Any hook that exits non-zero blocks the commit.

## Contract

- Receives no arguments
- Working directory is the repo root
- stdout is displayed; stderr is displayed on failure
- Exit 0 = pass. Exit non-zero = block the commit

## The 30-Second Rule

All pre-commit hooks combined must complete in under 30 seconds.
This is a gate, not a test suite. Full benchmarks, integration tests,
and multi-minute verification belong in CI or dedicated commands
(`hermes verify`, `hermes benchmark`).

If pre-commit exceeds 30 seconds, developers will bypass it.
Keep the gate fast. Put everything else in CI.

## Scope

These hooks enforce Platform repository policy — rules that apply to
every commit regardless of which tool created it. None depend on Hermes.
They are reusable across any project that adopts this gateway.

## Planned hooks

| Hook | Purpose | Est. Time |
|------|---------|-----------|
| `01-conventional-commits` | Reject commits that don't follow conventional commit format | < 1s |
| `02-large-file-guard` | Reject commits that add files over a size threshold | < 1s |
| `03-syntax-check` | ShellCheck for .sh, yamllint for .yaml, ruff for .py | ~5s |
| `04-formatting` | Auto-format or reject unformatted files | ~5s |
| `05-affected-tests` | Run unit tests for modules changed in this commit | ~15s |
| `06-architecture-guardrails` | Reject direct imports of hermes-agent internals from platform/ | < 1s |
