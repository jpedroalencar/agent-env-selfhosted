# Decision Log Template

Template for recording engineering and operational decisions. Each significant decision gets one entry. Entries are append-only — corrections add a new entry, never modify an existing one.

**Location:** Integrated into project memory or build log. Each entry is a dated record.

---

## Decision Record

```yaml
decision_id: DEC-YYYYMMDD-NNN
date: YYYY-MM-DD
author: <persona-name or human>
status: proposed | accepted | implemented | superseded
supersedes: <optional: decision_id this replaces>
superseded_by: <optional: decision_id that replaced this>
```

### Decision

<One-sentence summary of what was decided. Start with "We will..." or "We will not...">

### Context

<Background information. What problem were we solving? What prompted this decision? Include relevant technical, operational, or business context.>

### Alternatives Considered

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A | | | |
| B | | | |
| C | | | |

### Reasoning

<Why the chosen option was selected over the alternatives. Tie each pro/con to specific constraints or priorities (e.g., "Option A was chosen because it provides better security isolation, which is our highest priority in Phase 1.")>

### Impact

**Positive:**
- <expected benefit 1>
- <expected benefit 2>

**Negative / Trade-offs:**
- <trade-off 1>
- <trade-off 2>

**Risks:**
- <risk 1> — <mitigation>
- <risk 2> — <mitigation>

### Follow-Up Actions

| Action | Owner | Deadline | Status |
|--------|-------|----------|--------|
| | | YYYY-MM-DD | |
| | | YYYY-MM-DD | |

### Lessons Learned

<Optional. Added after implementation is complete. What did we learn from executing this decision? Would we make the same choice again?>

---

## Index

<!-- When maintaining multiple decision records, keep an index at the top of the file. -->

| ID | Date | Decision | Status | Author |
|----|------|----------|--------|--------|
| DEC-YYYYMMDD-NNN | YYYY-MM-DD | | accepted | |
| DEC-YYYYMMDD-NNN | YYYY-MM-DD | | superseded | |

---

## Usage Rules

1. **One record per decision.** If the same decision needs to be revisited later, create a new record — do not edit the old one.
2. **Supersede, don't delete.** If a decision is reversed, add the replacement record with `supersedes:` pointing to the original. Update the original's `superseded_by` field.
3. **Link to evidence.** Where relevant, include references to build log entries, pull requests, or external sources that informed the decision.
4. **Tag with domain.** Use tags in context to make decisions searchable (e.g., `#infrastructure`, `#security`, `#provider`).
5. **All personas may create entries.** Any persona can record a decision. Notify Operations Manager so the build log can be updated.
