"""
Bridges Hermes execution events to Platform telemetry.

Hermes emits events via callbacks during execution:
    step_callback, tool_complete_callback, tool_start_callback,
    thinking_callback, reasoning_callback, stream_delta_callback,
    clarify_callback

This module:
1. Registers Platform telemetry hooks during AIAgent construction
2. Translates raw Hermes callback data into TelemetryEvent schemas
3. Forwards events to platform/telemetry/collector.py

Does NOT: store, analyze, or interpret events.
"""

# Stub — implementation in Phase 6


def register_callbacks(agent, collector):
    """
    Register Platform telemetry hooks on a Hermes AIAgent instance.

    Args:
        agent: Hermes AIAgent instance (post-construction)
        collector: platform.telemetry.collector.TelemetryCollector
    """
    raise NotImplementedError("Phase 6 — implement callback registration")
