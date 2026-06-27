# Configuration

Reference documentation for the Hermes Agent configuration, environment variables, provider setup, and platform conventions.

**CRITICAL:** This document describes configuration *schemas and patterns*. Actual secrets, API keys, and tokens are stored in a local secrets file (`~/.config/hermes/secrets.env`) that is excluded from version control.

> **Provenance:** This document was consolidated from the repository's original `docs/configuration.md` and the root-level `CONFIGURATION.md` on 2026-06-24. Unique content from the root document has been merged into the appendix; the root file is now deprecated.

---

## 1. Hermes Configuration

### 1.1 Config File Location

```
~/.hermes/config.yaml
```

The configuration file follows Hermes Agent's YAML schema (config version 30). Key sections are documented below.

### 1.2 LLM Provider Configuration

```yaml
model:
  base_url: https://api.deepseek.com
  default: deepseek-v4-flash
  fallback:
    - openrouter
    - google/gemini-2.0-flash
  provider: deepseek
```

**Current setup:**
- **Primary:** DeepSeek (`deepseek-v4-flash`) via `api.deepseek.com`
- **Fallback 1:** OpenRouter (routes to the model specified `openrouter` prefix)
- **Fallback 2:** Google Gemini Flash via OpenRouter

**Provider keys** are NOT in config.yaml. They are:
- `DEEPSEEK_API_KEY` — stored in secrets.env, exported before agent context
- `OPENROUTER_API_KEY` — stored in secrets.env

### 1.3 Environment Variables

| Variable | Purpose | Location | Example |
|----------|---------|----------|---------|
| `GITHUB_TOKEN` | GitHub API and git authentication | `~/.config/hermes/secrets.env` | `ghp_...` |
| `DEEPSEEK_API_KEY` | DeepSeek LLM API authentication | `~/.config/hermes/secrets.env` | `sk-...` |
| `OPENROUTER_API_KEY` | OpenRouter API authentication | `~/.config/hermes/secrets.env` | `sk-...` |

All variables are stored in a single env file sourced before use:

```bash
source ~/.config/hermes/secrets.env
```

### 1.4 Telegram Bot Configuration

```yaml
gateway:
  telegram:
    enabled: true
    token: <BOT_TOKEN>  # Stored securely, redacted in logs
  platforms:
    telegram:
      extra:
        disable_topic_auto_rename: true
```

The bot token is stored in the config file but redacted by Hermes' security layer. Chat-level configuration includes:

- **Reactions:** Disabled (avoids noise in group chats)
- **Topic auto-rename:** Disabled (preserves user-set thread titles)

### 1.5 Agent Behavior

```yaml
agent:
  max_turns: 150                        # Max exchanges per session
  gateway_timeout: 1800                 # Session timeout (30 min)
  tool_use_enforcement: auto            # Auto-guidance for tool usage
  environment_probe: true               # Detect OS, Python, tooling
  reasoning_effort: medium              # Reasoning visibility level
```

### 1.6 Tools and Toolsets

| Toolset | Status | Purpose |
|---------|--------|---------|
| `web` | ✅ Enabled | Web search & content extraction |
| `browser` | ✅ Enabled | Browser automation |
| `terminal` | ✅ Enabled | Shell commands & processes |
| `file` | ✅ Enabled | File operations |
| `code_execution` | ✅ Enabled | Python sandbox for multi-step logic |
| `vision` | ✅ Enabled | Image analysis |
| `image_gen` | ✅ Enabled | Image generation |
| `video` | ❌ Disabled | Video analysis |
| `video_gen` | ❌ Disabled | Video generation |

### 1.7 Delegation Configuration

```yaml
delegation:
  max_concurrent_children: 3       # Max parallel subagents
  max_spawn_depth: 1               # Leaf agents cannot delegate further
  orchestrator_enabled: true       # Subagents can be orchestrators
  subagent_auto_approve: false     # Subagent actions require no approval
```

### 1.8 Memory Configuration

```yaml
memory:
  memory_enabled: true
  user_profile_enabled: true
  memory_char_limit: 2200          # Max chars for agent memory notes
  user_char_limit: 1375            # Max chars for user profile
  write_approval: false            # No approval needed for memory writes
  flush_min_turns: 6               # Min turns between memory nudges
```

### 1.9 Security Configuration

```yaml
security:
  allow_private_urls: false        # Block localhost/private IP web access
  redact_secrets: true             # Auto-redact tokens in outputs
  tirith_enabled: false            # TIRITH policy engine (off)
```

**Approvals:**

```yaml
approvals:
  mode: false                      # No approval prompts for actions
  timeout: 60
```

---

## 2. API Providers

### 2.1 DeepSeek (Primary)

| Property | Value |
|----------|-------|
| Endpoint | `https://api.deepseek.com` |
| Default Model | `deepseek-v4-flash` |
| Auth Method | API key (`DEEPSEEK_API_KEY`) |
| Role | Primary inference provider |

### 2.2 OpenRouter (Fallback)

| Property | Value |
|----------|-------|
| Endpoint | OpenRouter router |
| Fallback Model | `google/gemini-2.0-flash` |
| Auth Method | API key (`OPENROUTER_API_KEY`) |
| Features | Response caching enabled (300s TTL) |
| Role | Fallback when DeepSeek is unavailable |

---

## 3. Persona Architecture

### 3.1 Overview

The platform uses four specialist agent personas under a single Orchestrator profile:

| Persona | Responsible For |
|---------|----------------|
| **Orchestrator** | Coordination, routing, architecture decisions, reporting to John |
| **Financial Analyst (FA)** | Stocks, ETFs, valuation, earnings, macro, portfolio analysis |
| **Research Analyst (RA)** | Deep research, market intel, tech/legal/competitive analysis |
| **Dev** | Code, debugging, infrastructure, LXD, Hermes, APIs, automation |
| **Operations Manager (OM)** | Planning, docs, roadmaps, project management |

### 3.2 Persona Storage Layout

```
~/.hermes/skills/personas/
├── dev/SKILL.md
├── financial-analyst/SKILL.md
├── operations-manager/SKILL.md
└── research-analyst/SKILL.md

~/.hermes/personas/
├── dev/
│   ├── workspace/
│   └── memory.md
├── financial-analyst/
│   ├── workspace/
│   └── memory.md
├── operations-manager/
│   ├── workspace/
│   └── memory.md
├── research-analyst/
│   ├── workspace/
│   └── memory.md
└── orchestrator/
    └── workspace/
```

### 3.3 Routing Logic

- **High-confidence matches** → auto-assigned, no confirmation
- **Multiple relevant personas** → user chooses (labeled options)
- **Low confidence** → user asked for direction
- **Cross-domain tasks** → Orchestrator coordinates multiple personas

---

## 4. Repository Conventions

### 4.1 What Goes in This Repository

- **Documentation:** Architecture, deployment, configuration, build log, security
- **Memory schemas:** Templates and definitions for agent memory
- **Persona definitions:** SKILL.md files defining agent identities
- **Skill definitions:** Reusable workflow definitions
- **Diagrams:** Architecture diagrams (SVG, Excalidraw, screenshots)
- **Scripts:** Automation scripts for platform operations
- **Infrastructure config:** Infrastructure-as-code definitions (future)

### 4.2 What Does NOT Go in This Repository

- **Runtime memory:** Session state, conversation history, embeddings, vector stores
- **Credentials:** API keys, tokens, certificates, passwords
- **Logs:** Operational logs, debug output
- **Temporary workspaces:** Agent working directories
- **Build artifacts:** Compiled output, generated code
- **Application code:** Production applications built using the platform

### 4.3 .gitignore Protection

The repository `.gitignore` blocks:

- **Secrets:** `.env`, `secrets.env`, `.git-credentials`, `*.pem`, `*.key`
- **Caches:** `__pycache__/`, `tmp/`, `.DS_Store`
- **Python:** `.venv/`, `venv/`, `dist/`, `build/`
- **Storage:** `*.log`, `memory.db`, `vectorstore/`, `chroma/`, `qdrant/`
- **Hermes runtime:** `.hermes/` (except whitelisted patterns), `hermes-cron/`
- **Editors:** `.vscode/`, `.idea/`

---

## 5. Content Storage Conventions

Agent-generated content is stored under `~/.hermes/content/<agent-name>/`:

```
~/.hermes/content/
├── dev/
│   └── YYYY-MM-DD_short-kebab-title.md
├── financial-analyst/
│   └── YYYY-MM-DD_short-kebab-title.md
├── operations-manager/
│   └── YYYY-MM-DD_short-kebab-title.md
├── orchestrator/
│   └── YYYY-MM-DD_short-kebab-title.md
└── research-analyst/
    └── YYYY-MM-DD_short-kebab-title.md
```

**Rules:**
- Each agent writes to its own subdirectory only
- Filenames follow the pattern: `YYYY-MM-DD_short-kebab-title.md`
- Content is for reports, analyses, research, and generated artifacts
- Chats, clarifications, and status updates are NOT stored here
- All output references are confirmed by the agent in a one-line summary

---

## 6. Miscellaneous

### 6.1 Text-to-Speech

| Property | Value |
|----------|-------|
| Provider | Edge (default) |
| Voice | `en-US-AriaNeural` |

### 6.2 Speech-to-Text

| Property | Value |
|----------|-------|
| Provider | Local (default) |
| Model | `base` |

### 6.3 Context Compression

| Property | Value |
|----------|-------|
| Enabled | Yes |
| Threshold | 50% compressed ratio |
| Target | 20% of original |
| Protected turns | First 3, last 20 |

### 6.4 Cron Jobs

| Property | Value |
|----------|-------|
| Max parallel | Unlimited |
| Response wrapping | Enabled |
| Delivery | Fan-out to connected channels |

---

## Appendix: Configuration Reference (Consolidated from Root-Level Documentation)

The following sections were consolidated from the original root-level `CONFIGURATION.md` and provide supplementary reference material.

### A.1 Configuration Architecture

The platform uses a **layered configuration model**:

```
┌─────────────────────────────────────────┐
│  Global Hermes Config                    │
│  ~/.hermes/config.yaml                   │
│  Settings: profiles_dir, logging, etc.   │
├─────────────────────────────────────────┤
│  Per-Profile Config                      │
│  ~/.hermes/profiles/<name>/config.yaml   │
│  Settings: persona, tools, memory, etc.  │
├─────────────────────────────────────────┤
│  Core Memory (Per-Profile)               │
│  ~/.hermes/profiles/<name>/memories/core/│
│  Settings: identity, constraints, domain │
├─────────────────────────────────────────┤
│  Environment Variables                   │
│  Inherited from shell                    │
│  Settings: API keys, paths, preferences  │
└─────────────────────────────────────────┘
```

**Priority:** Environment variables override core memory. Core memory overrides per-profile config. Per-profile config overrides global config.

### A.2 Global Hermes Config Reference

**Location:** `~/.hermes/config.yaml`

```yaml
# Global Hermes Agent Configuration
hermes:
  version: "1.0"
  profiles_dir: "~/.hermes/profiles"

logging:
  level: "info"                             # debug | info | warn | error
  format: "json"                            # json | text
  output: "stdout"                          # stdout | file | syslog

profiles:
  default_persona: "orchestrator"
  allow_custom_profiles: true
```

| Setting | When to Change |
|---------|---------------|
| `logging.level` | Set to `debug` when troubleshooting a persona issue |
| `profiles.default_persona` | If you want a different default entry point |
| `hermes.profiles_dir` | If you move profiles to a different path |

### A.3 Memory Configuration Reference

Each profile's memory directory:

```
memories/
├── core/              # Permanent identity — NEVER modified by sessions
│   ├── domain.md      # Domain expertise, knowledge, and methodology
│   └── constraints.md # Boundaries, rules, and prohibitions
├── working/           # Session context — CLEARED between delegations
│   └── current-task.md
└── persistent/        # Cross-session learnings — ACCUMULATED over time
    ├── preferences.md
    └── patterns.md
```

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `memory.max_size_kb` | integer | 50 | Soft limit for total memory directory size (KB) |
| `memory.auto_clean` | boolean | true | If true, working memory is automatically cleared at session end |
| `memory.working_ttl` | integer (minutes) | null | If set, working memory older than this is automatically cleared |

### A.4 Environment Variables Reference

| Variable | Used By | Purpose |
|----------|---------|---------|
| `PATH` | All | Locate executables |
| `HOME` | All | Locate user home directory |
| `PYTHONPATH` | Dev, Fin Analyst | Additional Python import paths |
| `HERMES_CONFIG` | Hermes | Override global config path |

For credential management, use a `.env` file loaded at shell startup, never commit it to git, and rotate credentials regularly.

### A.5 Configuration Change Procedures

**Low-risk changes** (tool whitelist additions, memory updates, routing updates):
1. Edit the file
2. Test with a single command
3. Done

**Medium-risk changes** (tool whitelist removals, constraint changes):
1. Edit the file
2. Backup the previous version
3. Test with full workflow
4. Monitor for issues over 24 hours

**High-risk changes** (global config changes, profile deletions, credential config):
1. Take a full LXD snapshot backup
2. Document the change in the build log (`log/build-log.md`)
3. Make the change
4. Run full verification (`docs/deployment.md` verification checklist)
5. Monitor closely for 48 hours

### A.6 Configuration Validation

```bash
python3 -c "
import yaml, sys
try:
    with open(sys.argv[1]) as f:
        yaml.safe_load(f)
        print('Valid YAML')
except Exception as e:
    print(f'Invalid: {e}')
    sys.exit(1)
" ~/.hermes/profiles/financial-analyst/config.yaml
```

### A.7 Per-Profile Config Template: Profile Schema

```yaml
persona:
  name: "<Short Name>"
  role: "<One-line role description>"
  never_do: "<(Optional) Key constraint>"

tools:
  allowed:
    - <tool_name>
  blocked:
    - <tool_name>

memory:
  max_size_kb: <number>
  auto_clean: <boolean>
  working_ttl: <minutes>

skills:
  enabled:
    - <skill_name>
  disabled:
    - <skill_name>

cron:
  enabled: false
```
