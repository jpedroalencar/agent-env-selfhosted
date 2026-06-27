# Git Identity Policy

## Policy (frozen)

The Git Author always represents the human owner of the work.
The Git Committer represents the execution agent that created the commit.

- **Author:** John P. Alencar <johnpalencar@hotmail.com>
- **Committer:** johnalencar-agent <johnalencar-agent@users.noreply.github.com>

## Implementation

This policy is enforced through Git's native author/committer fields:

- Committer is set via `git config user.name` / `user.email` (local repo config)
- Author is set via `GIT_AUTHOR_NAME` / `GIT_AUTHOR_EMAIL` environment variables

No Co-authored-by trailers. No amend tricks. Pure Git identity separation.

## Verification

Every commit can be verified with:

    git log --format='Author: %an <%ae>%nCommitter: %cn <%ce>' -1

Expected:

    Author: John P. Alencar <johnpalencar@hotmail.com>
    Committer: johnalencar-agent <johnalencar-agent@users.noreply.github.com>

## Enforcement

This policy applies to every commit created by Hermes in every Platform repository.
