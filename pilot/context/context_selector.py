"""Context Selector — placeholder for metadata-first, token-budget-aware
retrieval of ``KnowledgeArtifact`` content.

The orchestration pipeline now looks like:

```
Gateway → ExecutionPlan → KnowledgeOrchestrator → ProviderRegistry →
KnowledgeProviders → KnowledgeArtifacts (metadata) → ContextSelector →
Lazy Content Loading → Context Assembly → Model → Evaluation
```

At the moment the selector is a *no‑op* that simply forwards the list of
artifacts. Future implementations will examine a ``ContextBudgetReport``
and decide which artifacts need their heavyweight ``content`` loaded,
potentially pulling from external caches or streaming large payloads only
when the token budget permits.
"""

from __future__ import annotations
from typing import List

# Import the concrete class for proper type checking. This does not cause a
# circular import because ``pilot.knowledge.artifact`` does not import the
# selector.
from pilot.knowledge.artifact import KnowledgeArtifact


def select_artifacts(plan, artifacts: List[KnowledgeArtifact]) -> List[KnowledgeArtifact]:
    """Metadata‑first selector stub.
+
+    Receives the ``ExecutionPlan`` and a list of ``KnowledgeArtifact`` objects.
+    The current implementation is a **no‑op** – it forwards all artifacts
+    unchanged. No token‑budget argument is present, matching the sprint’s
+    requirement to avoid placeholder budgeting.
+    """
+    # No‑op for now – keep all artifacts.
+    return artifacts
