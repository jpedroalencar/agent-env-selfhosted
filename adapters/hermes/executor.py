"""
Translates ExecutionPlan into Hermes Runtime parameters.

Single responsibility: mechanical field mapping.

    ExecutionPlan                    →  HermesExecutionParams
    ─────────────                       ─────────────────────
    plan.profile                   →  profile
    plan.skills                    →  skills
    plan.system_message_override   →  system_message
    plan.preloaded_context         →  user_message prefix
    plan.max_iterations            →  max_iterations
    plan.timeout_seconds           →  timeout
    plan.model_override            →  model

If the plan is invalid (missing required fields), rejects before
Hermes is invoked.

Does NOT: classify, plan, validate results, or modify Hermes internals.
"""

# Stub — implementation in Phase 1


def translate(plan):
    """
    Translate an ExecutionPlan into HermesExecutionParams.

    Raises PlanValidationError if the plan is missing required fields.
    """
    raise NotImplementedError("Phase 1 — implement plan-to-params translation")


class PlanValidationError(ValueError):
    """Raised when an ExecutionPlan fails validation before Hermes invocation."""
    pass
