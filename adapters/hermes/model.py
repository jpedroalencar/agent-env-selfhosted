"""
Model adapter — thin wrapper around OpenAI-compatible API.

Shortcuts:
  - Hardcoded to DeepSeek provider (what this deployment uses).
  - Reads API key from ~/.hermes/.env.
  - Uses the Hermes venv's OpenAI SDK.
  - No provider registry. No fallback. No streaming.
  - Future: Adapter will read provider config dynamically.
"""

from __future__ import annotations

import os
import subprocess
import sys


def _get_api_key() -> str:
    """Read DEEPSEEK_API_KEY from ~/.hermes/.env."""
    env_path = os.path.expanduser("~/.hermes/.env")
    if not os.path.exists(env_path):
        raise RuntimeError(f"Env file not found: {env_path}")

    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if line.startswith("DEEPSEEK_API_KEY="):
                return line.split("=", 1)[1].strip("'\"")

    raise RuntimeError("DEEPSEEK_API_KEY not found in .env")


def call_model(prompt: str, *, model: str = "deepseek-v4-pro") -> str:
    """Call the DeepSeek model with a prompt. Returns the response text.

    Uses the Hermes venv's Python to access the OpenAI SDK.
    """
    api_key = _get_api_key()
    venv_python = "/usr/local/lib/hermes-agent/venv/bin/python3"

    script = f'''
import os
os.environ["OPENAI_API_KEY"] = {api_key!r}
from openai import OpenAI

client = OpenAI(
    base_url="https://api.deepseek.com",
    api_key={api_key!r},
)

response = client.chat.completions.create(
    model={model!r},
    messages=[{{"role": "user", "content": {prompt!r}}}],
    temperature=0,
    max_tokens=256,
)

print(response.choices[0].message.content)
'''

    result = subprocess.run(
        [venv_python, "-c", script],
        capture_output=True,
        text=True,
        timeout=30,
        env={**os.environ, "OPENAI_API_KEY": api_key},
    )

    if result.returncode != 0:
        raise RuntimeError(f"Model call failed: {result.stderr.strip()}")

    return result.stdout.strip()
