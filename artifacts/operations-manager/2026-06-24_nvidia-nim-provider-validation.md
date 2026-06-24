---
title: NVIDIA NIM Provider Validation
persona: operations-manager
created: 2026-06-24
status: verified
tags: [nvidia, nim, provider, background, maintenance, delegation]
freshness_days: 90
summary: Validation of NVIDIA NIM as a background maintenance provider for Hermes Agent. All three priority models responding.
path: artifacts/operations-manager/2026-06-24_nvidia-nim-provider-validation.md
---

# NVIDIA NIM Provider Validation

| Field | Value |
|-------|-------|
| **Provider** | NVIDIA NIM |
| **Endpoint** | https://integrate.api.nvidia.com/v1 |
| **Auth** | API key via NVIDIA_API_KEY env var |
| **Primary Model** | meta/llama-3.3-70b-instruct |
| **Secondary** | qwen/qwen3-next-80b-a3b-instruct |
| **Emergency** | meta/llama-3.1-8b-instruct |
| **Validation Date** | 2026-06-24 |

## Test Results

| Model | Status |
|-------|--------|
| meta/llama-3.3-70b-instruct | ✅ Responding |
| qwen/qwen3-next-80b-a3b-instruct | ✅ Responding |
| meta/llama-3.1-8b-instruct | ✅ Responding |

## Configuration

- **Provider name:** nvidia (built-in Hermes provider)
- **Base URL:** https://integrate.api.nvidia.com/v1
- **API key env var:** NVIDIA_API_KEY
- **Models endpoint:** GET /v1/models — 121 models available

## Provider Strategy

- **Primary (interactive):** DeepSeek
- **Background (maintenance):** NVIDIA NIM
- **Fallback chain:** meta/llama-3.3-70b-instruct → qwen/qwen3-next-80b-a3b-instruct → meta/llama-3.1-8b-instruct
- **Delegation:** provider: nvidia, model: meta/llama-3.3-70b-instruct

## Rate Limiting

- **Assumed limit:** 40 req/min (NVIDIA free tier)
- **Safety margin:** Maximum 30 req/min
- **On 429 / ratelimit:** Stop immediately, defer task, retry on next scheduled execution
- **On unavailable:** Defer task, log reason, create warning artifact. Do NOT fall back to DeepSeek.

## Background Tasks (Allowed)

- Documentation Audit
- Architecture Review
- Knowledge Vault Audit
- Repository Health Review
- Technical Debt Review
- Backup Evidence Audit
- Operations Health Report
