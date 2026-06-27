"""
Reads Hermes configuration for Platform awareness.

The Platform needs to know what Hermes can do to produce valid
ExecutionPlans. This module reads Hermes config and exposes a
read-only view of:

    - Available providers and models
    - Enabled toolsets
    - Active profiles
    - Gateway platform status

Does NOT: write to Hermes configuration.
"""

# Stub — implementation in Phase 1


def read_providers():
    """Return available providers and models from Hermes config."""
    raise NotImplementedError("Phase 1 — implement config reading")


def read_toolsets():
    """Return enabled toolsets from Hermes config."""
    raise NotImplementedError("Phase 1 — implement config reading")


def read_profiles():
    """Return available profiles from Hermes config."""
    raise NotImplementedError("Phase 1 — implement config reading")
