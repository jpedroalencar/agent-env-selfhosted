# Agent Platform

Self-hosted AI agent platform running on an Ubuntu VPS using LXD containers, with a focus on security, operational simplicity, recoverability, and long-term maintainability.

---

## Overview

Agent Platform documents the design, deployment, and operation of a private AI agent environment built around Hermes.

Unlike traditional web applications, autonomous agents interact extensively with filesystems, development tools, repositories, scripts, and long-running processes. This project explores how to provide an agent with a realistic Linux environment while maintaining isolation, recoverability, and operational control.

The current deployment is private and intended for personal use. Public-facing services will only be introduced after operational procedures, backups, and security controls have been validated.

---

## Design Goals

The platform is built around five principles:

1. Reliability
2. Security
3. Maintainability
4. Simplicity
5. Scalability

When tradeoffs exist, preference is given to solutions that are easier to understand, operate, recover, and document.

---

## Current Architecture

```text
Ubuntu VPS
├── UFW Firewall
├── Fail2Ban
├── LXD
│   └── Hermes Container
└── Backup Storage
```

---

## Planned Architecture

```text
Internet
    ↓
Caddy
    ↓
Authentication
    ↓
Hermes Container
```

---

## Technology Stack

### Infrastructure

- Ubuntu 24.04 LTS
- LXD (Unprivileged Containers)
- UFW
- Fail2Ban

### Agent Runtime

- Hermes

### Planned Components

- Caddy Reverse Proxy
- OAuth Authentication
- Monitoring & Observability
- Public Demo Environment

---

## Key Design Decisions

### Private-First Deployment

The platform remains private during development to validate stability, backup procedures, recovery workflows, and security controls before introducing public access.

### LXD Instead of Docker

Hermes behaves more like a Linux user than a traditional web application.

During research, a recurring challenge in Docker-based deployments involved filesystem management, bind mounts, duplicated files, and agent confusion regarding volume boundaries.

LXD provides a complete Linux environment, natural filesystem behavior, snapshot support, simplified backup and migration, and strong isolation from the host system.

### VPS Instead of Local Hosting

Running the platform on a VPS provides continuous availability, remote administration, dedicated resources, and easier disaster recovery.

---

## Documentation

| File                    | Purpose                                            |
| ----------------------- | -------------------------------------------------- |
| docs/architecture.md    | System architecture and design decisions           |
| docs/deployment.md      | VPS provisioning and Hermes deployment             |
| docs/security.md        | Security controls and hardening                    |
| docs/backup-recovery.md | Backup, migration, and disaster recovery           |
| docs/build-log.md       | Project decisions, lessons learned, and milestones |
| docs/roadmap.md         | Future enhancements and platform direction         |

---

## Roadmap

### Phase 1 – Foundation

- VPS deployment
- LXD containerization
- Hermes installation
- Backup procedures
- Recovery procedures

### Phase 2 – Access Layer

- Caddy reverse proxy
- HTTPS
- Authentication
- Domain integration

### Phase 3 – Operations

- Monitoring
- Metrics
- Health checks
- Automated backups
- Alerting

### Phase 4 – Public Presence

- Website
- Architecture diagrams
- Public read-only demo

---

## Status

Active Development

Current focus:

- VPS provisioning
- LXD deployment
- Hermes installation

---

## Philosophy

The goal is to build a secure, maintainable, and recoverable platform capable of supporting autonomous agents over the long term while documenting the engineering decisions, tradeoffs, and lessons learned throughout the process.
