# Agent Configuration

Platform-owned agent assets. These files define what personas know,
how memory is structured, and which skills are available.

These files are the **canonical source** for persona definitions.
Hermes Runtime loads operational versions derived from these definitions.

## Directory

- `personas/` — Persona identity definitions (responsibilities, authority boundaries, routing rules)
- `skills/` — Domain skill definitions (future: migrated from `~/.hermes/skills/`)

## Relationship to Hermes Runtime

The Hermes Runtime at `~/.hermes/skills/personas/` contains operational
SKILL.md files. These are derived from the canonical definitions here.
During Phase 2 migration, the in-repo definitions become authoritative
and the Hermes versions are updated to match.
