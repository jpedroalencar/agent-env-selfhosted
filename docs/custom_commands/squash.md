# /squash Command

## Overview

Consolidate all commits on a sprint branch into a single clean commit before PR creation. This gives the effect of squash merge while preserving correct authorship.

## Syntax

```
/squash                              — auto-generate commit message from commits
/squash "commit message"             — custom commit message
```

## What It Does

1. Verifies you're on a `sprint/` branch
2. Counts commits ahead of `origin/main`
3. Squashes all commits into one using `git reset --soft`
4. Creates a new commit with correct authorship:
   - **Author:** John P. Alencar (the human)
   - **Committer:** johnalencar-agent (the agent)
5. Force pushes the consolidated branch
6. PR automatically updates on GitHub

## Examples

```bash
# Auto-generate commit message
/squash

# Custom commit message
/squash "feat: add user authentication and JWT support"
```

## Auto-Generated Commit Message

When no message is provided, the script generates:

```
feat: sprint 2026-07-01-1

Consolidated from 8 commits:

- fix: use regular merge instead of squash to preserve authorship
- fix: use GitHub REST API directly instead of gh CLI
- fix: simplify auto-pr.yml heredoc for PR body
...
```

## Workflow Integration

```
1. Agent commits to sprint/ branch (multiple commits)
2. PR is created automatically (shows all commits)
3. You review the PR
4. Run /squash to consolidate
5. Click "Approve" → regular merge preserves authorship
```

## Script Location

`scripts/sprint-finalize.sh` in the agent-env-selfhosted repo.

## Patching After Hermes Updates

After `hermes update`, run:

```bash
scripts/patch-hermes-squash.sh
```

This re-applies the `/squash` command to the new Hermes installation.

## Files Modified

1. `hermes_cli/commands.py` — Added `CommandDef("squash", ...)`
2. `hermes_cli/cli_commands_mixin.py` — Added `_handle_squash_command()`
3. `gateway/slash_commands.py` — Added `_handle_squash_command()` for Telegram
