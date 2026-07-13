"""
Entry point for the Agent Platform — `python -m pilot`.

This is the "plug": the runnable harness entry point that wires the
Platform intelligence layer (pilot/) to an execution adapter and runs a
request end-to-end. Without this module the pipeline (gateway ->
ExecutionPlan -> adapter -> model) could only be invoked from tests.

Usage:
    python -m pilot --prompt "What is the capital of France?"
    python -m pilot --prompt "Summarize the Q2 report" --mock

By default the HermesAdapter is used, which calls the configured LLM
provider. Pass --mock to skip the real model call and return the
assembled prompt — useful for verifying the pipeline without API
credits.
"""
from __future__ import annotations

import argparse
import json
import sys
from typing import Optional

from pilot.gateway import handle_request
from pilot.agent_adapter import AgentAdapter


class EchoAdapter:
    """Mock adapter used with --mock: echoes the assembled prompt back.

    Lets you run the full Platform pipeline (parse -> classify -> plan ->
    knowledge -> context -> prompt) without consuming LLM API credits.
    """

    def execute(self, prompt: str) -> str:
        return f"[mock response]\n\n--- assembled prompt ---\n{prompt}"


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python -m pilot",
        description="Run the Agent Platform pipeline on a request.",
    )
    parser.add_argument(
        "--prompt",
        "-p",
        required=True,
        help="The user request to process through the platform.",
    )
    parser.add_argument(
        "--mock",
        action="store_true",
        help="Use a mock adapter (no real LLM call).",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit the full pipeline trace as JSON instead of plain text.",
    )
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = _build_arg_parser().parse_args(argv)

    adapter: Optional[AgentAdapter] = EchoAdapter() if args.mock else None

    try:
        result = handle_request(args.prompt, adapter=adapter)
    except Exception as exc:  # surface pipeline errors cleanly
        print(f"error: {exc}", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps(result, indent=2, default=str))
    else:
        print(f"intent:   {result['intent']}")
        print(f"profile:  {result['plan']['profile']}")
        print(f"skills:   {', '.join(result['plan']['skills']) or '(none)'}")
        print(f"providers:{', '.join(result['plan']['knowledge_providers']) or '(none)'}")
        print("-" * 60)
        print(result["response"])

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
