# Git Identity Policy

## Policy (frozen)

The Git Author always represents the human owner of the work.
The Git Committer represents the execution agent that created the commit.

- **Author:** John P. Alencar <johnpalencar@hotmail.com>
- **Committer:** johnalencar-agent <johnalencar-agent@users.noreply.github.com>

## Implementation

This policy is enforced through `scripts/git-commit.sh` — the single
entry point for every Platform commit.

- **Committer** is set via `git config user.name` / `user.email` in the local repo config (`johnalencar-agent`)
- **Author** is set deterministically inside `scripts/git-commit.sh` via `GIT_AUTHOR_NAME` / `GIT_AUTHOR_EMAIL`
- The wrapper script **verifies** the identity split after every commit and exits with code 2 on violation

No environment variable dependencies. No shell state assumptions.
Restart the container, switch execution environments, run from a cron
job — every commit through `scripts/git-commit.sh` has the same identity.

Usage:

    scripts/git-commit.sh "commit message"
    scripts/git-commit.sh -m "commit message"
    scripts/git-commit.sh -am "commit message"

All arguments pass through to `git commit` unchanged.

## Verification

Every commit can be verified with:

    git log --format='Author: %an <%ae>%nCommitter: %cn <%ce>' -1

Expected:

    Author: John P. Alencar <johnpalencar@hotmail.com>
    Committer: johnalencar-agent <johnalencar-agent@users.noreply.github.com>

## Enforcement

This policy applies to every commit created by Hermes in every Platform repository.
