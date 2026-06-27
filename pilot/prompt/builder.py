"""
Prompt Builder — assembles the final prompt string.

Minimal edition: hardcoded template. No abstraction. No caching.
"""

from __future__ import annotations


SYSTEM_PROMPT = """You are a helpful, concise assistant. Answer the user's question
using only the provided context. If the context doesn't contain
the answer, say so. Do not fabricate information."""


def build_prompt(context: str, question: str) -> str:
    """Build a prompt from context and a user question.

    Returns the full prompt string ready for the model.
    """
    return f"""{SYSTEM_PROMPT}

## Context

{context}

## Question

{question}"""
