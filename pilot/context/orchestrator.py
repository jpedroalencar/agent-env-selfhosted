"""Legacy orchestrator module removed — see ``pilot.context.knowledge_orchestrator``.

This file existed for backward compatibility but has been fully retired. All
runtime code should import ``pilot.context.knowledge_orchestrator`` instead.
"""

def run(*args, **kwargs):
    """Placeholder that raises to alert any stray imports.

    The original orchestration logic now lives in
    ``pilot.context.knowledge_orchestrator.run``. If this function is called,
    it means an outdated import path is still in use.
    """
    raise ImportError(
        "Legacy orchestrator removed. Import ``pilot.context.knowledge_orchestrator`` and call its ``run`` function instead."
    )
