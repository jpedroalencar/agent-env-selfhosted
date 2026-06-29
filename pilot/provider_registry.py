"""
Provider Registry – central in-memory registry for KnowledgeProvider classes.

Provides:
- `register(name: str, provider_cls: type)` – add or replace a provider.
- `unregister(name: str)` – remove a provider.
- `get_provider(name: str) -> type` – fetch the class (raises KeyError).
- `list_providers() -> list[str]` – deterministic list sorted by registration order.

Thread‑safe via a simple module‑level lock.
"""

from __future__ import annotations

import threading
from typing import Dict, Type

# Registry storage – mapping name -> provider class
_registry: Dict[str, Type] = {}
_lock = threading.Lock()


def register(name: str, provider_cls: Type) -> None:
    """Register a provider class under ``name``.

    Overwrites any existing entry with the same name.
    """
    with _lock:
        _registry[name] = provider_cls


def unregister(name: str) -> None:
    """Remove a provider from the registry. No‑op if absent."""
    with _lock:
        _registry.pop(name, None)


def get_provider(name: str) -> Type:
    """Return the provider class for ``name``.

    Raises ``KeyError`` if the name is not registered.
    """
    with _lock:
        try:
            return _registry[name]
        except KeyError as exc:
            raise KeyError(f"Provider '{name}' not found in ProviderRegistry") from exc


def list_providers() -> list[str]:
    """Return a deterministic list of registered provider names."""
    with _lock:
        return sorted(_registry.keys())
