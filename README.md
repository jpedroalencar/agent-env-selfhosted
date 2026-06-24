# Agent Platform

Self-hosted AI agent platform running on an **Oracle Cloud VPS** using **LXC containers**, with a focus on security, operational simplicity, recoverability, and long-term maintainability.

> **Disclaimer:** This repository documents a self-hosted AI agent platform currently in active development. Items listed under "Planned Architecture" or "Roadmap" describe intended future states, not implemented features.

---

## Overview

Agent Platform documents the design, deployment, and operation of a private AI agent environment built around [Hermes Agent](https://hermes-agent.nousresearch.com).

Unlike traditional web applications, autonomous agents interact extensively with filesystems, development tools, repositories, scripts, and long-running processes. This project explores how to provide an agent with a realistic Linux environment while maintaining isolation, recoverability, and operational control.

The current deployment is private and intended for personal use. Public-facing services will only be introduced after operational procedures, backups, and security controls have been validated.

---

## Current Architecture

```text
Oracle Cloud VPS
└── LXC Container (Hermes — Debian 12, aarch64)
    ├── Hermes Agent v0.17.0
    │   ├── Provider: DeepSeek (primary)
    │   ├── Fallback: OpenRouter → Gemini Flash
    │   └── Platform: Telegram
    └── Local Secret Store
```

- **Host:** Oracle Cloud Infrastructure (OCI), ARM-based (Ampere A1 / Neoverse-N1)
- **Hypervisor:** LXD on host Ubuntu — one unprivileged LXC container
- **Guest:** Debian 12 Bookworm, 2 vCPUs, 8 GB RAM, 40 GB disk
- **Agent Runtime:** Hermes Agent v0.17.0 running natively in the container
- **LLM Backend:** DeepSeek via API (deepseek-v4-flash), OpenRouter as fallback
- **Chat Interface:** Telegram (primary), CLI (direct)
- **Auth:** GitHub Personal Access Token stored in local secrets file
- **Firewall:** UFW on host (container outbound-only)

## Planned Architecture

```text
Internet
    ↓
Caddy (reverse proxy, HTTPS)
    ↓
OAuth Authentication
    ↓
Hermes Container
    ├── Web Dashboard
    └── Telegram Gateway
```

The planned architecture adds a public access layer with a Caddy reverse proxy, HTTPS termination, and OAuth authentication. This is **not yet implemented**.

---

## Technology Stack

### Infrastructure

| Component | Current | Notes |
|-----------|---------|-------|
| VPS Provider | Oracle Cloud (OCI) | ARM-based Ampere A1 tier |
| Host OS | Ubuntu 24.04 LTS (host) | Kernel: 6.17.0-1011-oracle |
| Container Runtime | LXD | Unprivileged LXC containers |
| Guest OS | Debian 12 (Bookworm) | aarch64 |
| Firewall (Host) | UFW | Inbound-restricted |
| Intrusion Prevention | Fail2Ban (Host) | SSH brute force protection |

### Agent Runtime

| Component | Version | Notes |
|-----------|---------|-------|
| Hermes Agent | v0.17.0 | `/usr/local/lib/hermes-agent` |
| Python | 3.11.2 | System Python |
| OpenAI SDK | 2.24.0 | Hermes dependency |

### LLM Providers

| Provider | Model | Role |
|----------|-------|------|
| DeepSeek | deepseek-v4-flash | Primary inference |
| OpenRouter | google/gemini-2.0-flash | Fallback |

### Connected Platforms

| Platform | Role | Status |
|----------|------|--------|
| Telegram | Primary chat interface | ✅ Connected |
| GitHub | Repository & automation | ✅ Connected |

---

## Design Decisions

### Private-First Deployment

The platform remains private during development to validate stability, backup procedures, recovery workflows, and security controls before introducing public access.

### LXC/LXD Instead of Docker

Hermes behaves more like a Linux user than a traditional web application. LXD provides a complete Linux environment, natural filesystem behavior, snapshot support, simplified backup and migration, and strong isolation from the host — all without the filesystem abstraction overhead of Docker bind mounts.

### VPS Instead of Local Hosting

Running the platform on a VPS provides continuous availability, remote administration, dedicated resources, and easier disaster recovery compared to a local machine.

### ARM Architecture

Oracle Cloud's free-tier Ampere A1 ARM instances offer competitive performance-per-dollar for LLM API-based agent workloads, which are I/O and network-bound rather than compute-bound.

---

## Repository Structure

```
├── agent/
│   ├── memory/           # Memory schemas, templates, and prompt definitions
│   ├── personas/         # Specialist agent persona definitions
│   └── skills/           # Reusable skill definitions
├── apps/                 # Application definitions built on the platform
├── artifacts/            # Knowledge Vault — curated deliverables and generated outputs
│   ├── index.md          # Vault index with metadata schema (title, persona, status, tags, freshness, summary, path)
│   ├── research-analyst/ # Research reports, competitive intelligence, literature reviews
│   ├── financial-analyst/# Investment research, valuation reports, earnings reviews
│   ├── dev/              # Technical plans and architecture documents
│   └── operations-manager/ # Operational runbooks and procedures
├── diagrams/             # Architecture and infrastructure diagrams (SVG, Excalidraw)
├── docs/                 # Platform documentation
│   ├── architecture.md   # System architecture and design decisions
│   ├── build-log.md      # Project decisions, lessons learned, milestones
│   ├── configuration.md  # Configuration reference
│   ├── deployment.md     # VPS provisioning and deployment
│   ├── operations.md     # Maintainer runbook and SOPs
│   ├── security.md       # Threat model, access control, network defenses
│   ├── reviews/          # Capability review and completion reports
│   │   ├── backup-phase-completion.md          # Backup Phase 1 + 1.1 completion report
│   │   └── knowledge-vault-phase1-review.md    # Knowledge Vault Phase 1 validation review
│   └── workflows/        # Agent workflow definitions
│       ├── artifact-pipeline.md   # Artifact generation and storage workflow
│       ├── knowledge-vault.md     # Knowledge Vault retrieval-before-research workflow
│       └── research-pipeline.md   # Research Analyst execution sequence
├── infra/                # Infrastructure configuration (Not yet populated)
├── logs/                 # Operational telemetry and logs (gitignored)
├── scripts/              # Automation and utility scripts
│   ├── backup-container.sh    # LXD container backup
│   ├── generate-artifact.sh   # Artifact generation and storage
│   ├── register-artifact.sh   # Knowledge Vault registration with metadata validation
│   └── restore-container.sh   # LXD container restore
├── screenshots/          # Platform screenshots and diagrams
├── workspaces/           # Temporary agent workspaces (gitignored contents)
├── .gitignore            # Security-hardened exclusion rules
├── LICENSE               # License file
└── README.md             # This file
```

---

## Current Status

**Phase 1 – Foundation — In Progress**

| Component | Status | Notes |
|-----------|--------|-------|
| VPS Provisioning | ✅ Complete | Oracle Cloud, ARM, Debian 12 |
| LXC Container | ✅ Complete | Unprivileged LXD container |
| Hermes Installation | ✅ Complete | v0.17.0 |
| GitHub Integration | ✅ Complete | Dedicated automation account |
| Repository Structure | ✅ Complete | This repository |
| Secret Management | ✅ Complete | Local secrets file, no Bitwarden |
| Knowledge Vault | ✅ Complete | Phase 1 — filesystem-based knowledge reuse layer. 5 artifacts registered across Research Analyst, Financial Analyst, and Dev personas. Retrieval-before-research workflow operational. See [docs/workflows/knowledge-vault.md](docs/workflows/knowledge-vault.md). |
| Backup & Recovery | ✅ Complete | Phase 1 + 1.1 — LXD snapshot backup with automated retention, restore script with safety features, and host validation evidence injection. See [docs/backup-recovery.md](docs/backup-recovery.md) and [docs/reviews/backup-phase-completion.md](docs/reviews/backup-phase-completion.md). |

---

## Roadmap

### Phase 2 — Knowledge Vault & Access Layer (Planned)

**Knowledge Vault:**
- Extend vault to Dev and Operations Manager personas
- Cross-session vault awareness (auto-load index at session start)
- Auto-compute index statistics
- Cron-based stale artifact checking
- Staleness-aware automatic refresh for fast-moving topics

**Access Layer:**
- Caddy reverse proxy
- HTTPS termination (Let's Encrypt / ACME)
- OAuth authentication
- Web dashboard access
- Domain integration

### Phase 3 – Operations & Observability (Planned)

**Backup Enhancements:**
- Configure cron scheduling for automated daily backups
- Commit evidence artifacts to git automatically
- Telegram notification on backup success/failure
- Off-site replication (rsync/S3-compatible)
- Quarterly restore drill

**General Operations:**
- Monitoring and metrics
- Health checks
- Alerting
- Scheduled cron jobs

### Phase 4 – Public Presence (Planned)

- Public website
- Published architecture diagrams
- Public read-only demo environment

---

## Philosophy

The goal is to build a secure, maintainable, and recoverable platform capable of supporting autonomous agents over the long term while documenting the engineering decisions, tradeoffs, and lessons learned throughout the process.
