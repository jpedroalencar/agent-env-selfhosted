# Agent Configuration

Platform-owned agent assets. These files define what personas know,
how memory is structured, and which skills are available.

These files are the **canonical source** for persona definitions.
Hermes Runtime loads operational versions derived from these definitions.

## Conceptual Boundaries

Three distinct concepts. Keep them separate.

| Concept | Answers | Current Location | Provider |
|---------|---------|-----------------|----------|
| **Personas** | *Who* is doing the work | `agent/personas/` | ConfigProvider (routing) |
| **Skills** | *How* to do the work | `agent/skills/` | (future: skill loader) |
| **Artifacts** | *What* was learned | `artifacts/` | Knowledge Vault |

**Maintenance rule:** Revisit this boundary only if implementation
creates duplication, shared retrieval behavior, or persistent ambiguity
about which concept owns a piece of content.

A persona definition describes a role — its responsibilities, authority,
and boundaries. A skill describes a procedure — steps to follow to
accomplish a task. An artifact describes a result — knowledge produced
by executing a persona with its skills. Do not collapse these into a
single directory. Do not put persona identity in skills. Do not put
skill procedures in artifacts. If you're unsure which bucket something
belongs in, it probably doesn't belong in any of them yet.

## Directory

- `personas/` — Persona identity definitions (responsibilities, authority boundaries, routing rules)
- `skills/` — Domain skill definitions (future: migrated from `~/.hermes/skills/`)

## Relationship to Hermes Runtime

The Hermes Runtime at `~/.hermes/skills/personas/` contains operational
SKILL.md files. These are derived from the canonical definitions here.
During Phase 2 migration, the in-repo definitions become authoritative
and the Hermes versions are updated to match.
