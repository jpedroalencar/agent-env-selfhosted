# Git Identity Policy

## Policy (frozen)

The Git Author always represents the human owner of the work.
The Git Committer represents the execution agent that created the commit.

- **Author:** John P. Alencar <johnpalencar@hotmail.com>
- **Committer:** johnalencar-agent <johnalencar-agent@users.noreply.github.com>

No Co-authored-by trailers. No amend tricks. Pure Git identity separation using the native Author/Committer fields.

## Supported Commit Path

Direct `git commit` is unsupported. Every Platform commit flows through:

```
scripts/git-commit.sh
```

This is the engineering gateway. It runs every commit through a pipeline:

```
Phase 0 — Pre-commit hooks (scripts/hooks/pre-commit.d/)
    → commit message validation
    → syntax check
    → test run
    (future — currently empty)

Phase 1 — Commit
    → set deterministic author identity
    → execute git commit

Phase 2 — Post-commit hooks (scripts/hooks/post-commit.d/)
    → verify author/committer identity split
    → verify commit message format
    → auto-push
    (future — currently empty)
```

Any pre-commit hook that exits non-zero blocks the commit.
Post-commit hook failures are reported but do not roll back.

## Identity Enforcement

- **Committer** is set via `git config user.name` / `user.email` in the local repo config (`johnalencar-agent`)
- **Author** is set deterministically inside `scripts/git-commit.sh` via `GIT_AUTHOR_NAME` / `GIT_AUTHOR_EMAIL`
- The wrapper verifies the identity split after every commit and exits code 2 on violation

No environment variable dependencies. No shell state assumptions.
Restart the container, switch execution environments, run from a cron
job — every commit through `scripts/git-commit.sh` has the same identity.

## Usage

```
scripts/git-commit.sh "commit message"
scripts/git-commit.sh -m "commit message"
scripts/git-commit.sh -am "commit message"
```

All arguments pass through to `git commit` unchanged.

## Verification

Every commit can be verified with:

```
git log --format='Author: %an <%ae>%nCommitter: %cn <%ce>' -1
```

Expected:

```
Author: John P. Alencar <johnpalencar@hotmail.com>
Committer: johnalencar-agent <johnalencar-agent@users.noreply.github.com>
```

## Enforcement

This policy applies to every commit created by Hermes in every Platform repository.
