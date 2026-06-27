# Context Planner Migration — Analysis

**Architecture v3.0 (frozen). No redesign. No code.**

---

## 1. Migration Matrix

| Module | Classification | Rationale |
|--------|---------------|-----------|
| **_parser.py** | **Reuse unchanged** | Pure regex + string predicates. Extracts signals from raw text into `ParsedRequest`. No Hermes dependency. No Platform dependency. 11 regex patterns, 5 signal categories. Directly usable by Platform Dispatch. |
| **_classifier.py** | **Reuse unchanged** | Decision tree mapping `ParsedRequest` → `RequestShape`. 7 rules, prioritized, deterministic. The output `RequestShape` enum (CODE_CHANGE, RESEARCH, CASUAL_CONVERSATION, etc.) maps 1:1 to Platform intents. |
| **_types.py** (select types) | **Adapt** | Keep: `ParsedRequest`, `RequestShape`, `SessionSnapshot`, `ContextPlannerInput`. Discard: `RetrievalType`, `RetrievalItem`, `RetrievalPlan`, `Rule`, `RuleCondition`, `RuleSource`, `RawRetrievalAction`, `OrderedRetrievalAction`. These are coupled to the old RetrievalPlan paradigm. |
| **_rule_engine.py** | **Replace** | Evaluates rules to produce retrieval actions. Tightly coupled to `RetrievalType` and `RetrievalPlan`. The Platform replaces this with `ConfigProvider.lookup(intent)` — a deterministic lookup, not a rule evaluation. The rules describe WHAT to retrieve; the Platform's Knowledge Resolver decides that. |
| **_dependency_resolver.py** | **Remove** | Orders retrieval actions by type dependency (TOOL_PREFLIGHT → CONFIG → SKILL → MEMORY → SESSION). The Platform queries providers sequentially (config → vault → web) with priority from routing.yaml. No dependency graph needed. |
| **_plan_compiler.py** | **Replace** | Assembles `RetrievalPlan` from ordered actions. The Platform produces `ExecutionPlan` instead. The budget logic (token allocation by priority) should move to the Platform's Context Strategy when implemented. |
| **Budget logic** (in plan_compiler) | **Adapt** | Token budget allocation by priority tier (HIGH/MEDIUM/LOW). Valuable but belongs in Platform Context Strategy, not in the planner. Preserve the algorithm; move it when Context Strategy is implemented. |
| **ContextPlanner class** (`__init__.py`) | **Adapt** | Orchestrates the 5-step pipeline. Keep steps 1-2 (parse + classify). Replace steps 3-5 (rules → deps → compile) with ConfigProvider.lookup() + ExecutionPlan construction. The 50ms time budget and fallback-to-safe-default pattern are valuable. |

---

## 2. Dependency Diagrams

### Old Pipeline (Hermes Context Planner)

```
ContextPlannerInput
       │
       ▼
  ┌─────────┐
  │ Parser  │  _parser.py          ← REUSE UNCHANGED
  └────┬────┘
       │ ParsedRequest
       ▼
  ┌───────────┐
  │ Classifier│  _classifier.py     ← REUSE UNCHANGED
  └─────┬─────┘
        │ RequestShape
        ▼
  ┌───────────┐
  │Rule Engine│  _rule_engine.py    ← REPLACE
  └─────┬─────┘
        │ [RawRetrievalAction, ...]
        ▼
  ┌─────────────────┐
  │Dependency Resolver│  _dependency_resolver.py  ← REMOVE
  └────────┬────────┘
           │ [OrderedRetrievalAction, ...]
           ▼
  ┌──────────────┐
  │Plan Compiler │  _plan_compiler.py  ← REPLACE
  └──────┬───────┘
         │ RetrievalPlan
         ▼
     Executor
```

### New Pipeline (Platform Dispatch)

```
ContextPlannerInput
       │
       ▼
  ┌─────────┐
  │ Parser  │  _parser.py              ← REUSED UNCHANGED
  └────┬────┘
       │ ParsedRequest
       ▼
  ┌───────────┐
  │ Classifier│  _classifier.py         ← REUSED UNCHANGED
  └─────┬─────┘
        │ RequestShape
        ▼
  ┌──────────────────┐
  │IntentMapper       │  NEW — 8-line dict  ← REPLACES rule engine
  │shape → intent     │
  └─────┬────────────┘
        │ intent string
        ▼
  ┌──────────────┐
  │ConfigProvider │  pilot/config_provider.py  ← ALREADY EXISTS
  │.lookup()      │
  └──────┬───────┘
         │ RoutingRule
         ▼
  ┌──────────────────┐
  │ExecutionPlan      │  pilot/dispatch/plan.py  ← ALREADY EXISTS
  │constructor        │
  └──────┬───────────┘
         │ ExecutionPlan
         ▼
     Platform Gateway
```

### What disappears

The entire back half of the Hermes pipeline — rule engine, dependency resolver, plan compiler — is replaced by `ConfigProvider.lookup()` + `ExecutionPlan()`. This is not a loss; the Platform's architecture makes these components unnecessary because:

1. **Rules are replaced by routing.yaml.** Instead of evaluating rules to determine what to retrieve, the Platform declares intent→profile mappings in a YAML file read by ConfigProvider.
2. **Dependencies are replaced by provider ordering.** Instead of resolving type-based dependencies, the Platform queries providers in priority order (config → vault → web).
3. **Plan compilation is replaced by ExecutionPlan construction.** Instead of assembling a RetrievalPlan with retrieval items, the Platform builds an ExecutionPlan with profile, skills, memory tier, and knowledge providers.

---

## 3. Integration Map: RequestShape → Platform Intent

The `RequestShape` enum maps directly to Platform intents:

| RequestShape | Platform Intent | ConfigProvider Rule |
|-------------|-----------------|---------------------|
| `CODE_CHANGE` | `code_change` | profile=dev |
| `CODE_QUESTION` | `code_question` | profile=dev |
| `CONFIG_CHANGE` | (map to `hermes_self_service` or new intent) | profile=dev |
| `HERMES_SELF_SERVICE` | (new intent: `hermes_config`) | (needs routing rule) |
| `RESEARCH` | `research` | profile=research-analyst |
| `CASUAL_CONVERSATION` | `casual` | profile=orchestrator |
| `MULTI_STEP_WORKFLOW` | `multi_step` | profile=orchestrator |
| `AMBIGUOUS` | `ambiguous` | profile=orchestrator |

Note: `CONFIG_CHANGE` and `HERMES_SELF_SERVICE` have no direct Platform intent. These map to the Orchestrator persona in the current routing config. A new intent (`hermes_config`) could be added later.

---

## 4. What to Copy into the Platform

Three files, no modifications:

```
hermes-agent/context_planner/_parser.py       → pilot/dispatch/_parser.py
hermes-agent/context_planner/_classifier.py   → pilot/dispatch/_classifier.py
hermes-agent/context_planner/_types.py        → pilot/dispatch/_types.py
                                               (subset: ParsedRequest, RequestShape,
                                                SessionSnapshot, ContextPlannerInput)
```

The `_types.py` copy should be pruned — keep only the types needed by parser and classifier. Discard `RetrievalType`, `RetrievalItem`, `RetrievalPlan`, `Rule`, `RuleCondition`, `RuleSource`, `RawRetrievalAction`, `OrderedRetrievalAction`, `Priority` (unless budget logic is preserved).

---

## 5. Minimal Migration Plan

| Step | Action | Files | Lines |
|------|--------|-------|-------|
| 1 | Copy `_parser.py` into Platform | `pilot/dispatch/_parser.py` | 273 (unchanged) |
| 2 | Copy `_classifier.py` into Platform | `pilot/dispatch/_classifier.py` | 198 (unchanged) |
| 3 | Copy and prune `_types.py` into Platform | `pilot/dispatch/_types.py` | ~100 (pruned from 213) |
| 4 | Add `IntentMapper` — shape → intent | `pilot/dispatch/intent_mapper.py` | ~15 lines |
| 5 | Wire into `gateway.py` — replace hardcoded `intent = "financial_analysis"` | `pilot/gateway.py` | ~10 lines changed |
| 6 | Test: arbitrary user message → correct ExecutionPlan | Tests | ~30 lines |

**Total:** 3 files copied (571 lines from Hermes, pruned to ~470), 2 files modified, 1 new file.

### What is NOT copied

- `_rule_engine.py` (490 lines) — replaced by ConfigProvider
- `_dependency_resolver.py` (201 lines) — replaced by provider ordering
- `_plan_compiler.py` (188 lines) — replaced by ExecutionPlan constructor
- `__init__.py` ContextPlanner class (227 lines) — replaced by gateway.py orchestrator

**~1,100 lines of Hermes code replaced by ~50 lines of Platform code.** The Platform's architecture makes rule evaluation, dependency resolution, and plan compilation unnecessary because routing is declarative (routing.yaml) and retrieval is sequential (provider ordering).
