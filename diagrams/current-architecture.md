# Current Architecture

Mermaid architecture diagram for the self-hosted AI agent platform.

**Note:** This file is a source document for manual SVG export. The canonical editable source is `diagrams/current-architecture.drawio`.

---

## Architecture Overview

```mermaid
architecture-beta
    group vps(cloud)[Oracle Cloud VPS - Ubuntu 24.04 LTS]

    group container(container)[LXC Container - Debian 12 Bookworm]
    group hostBoundary[Host isolation boundary]
    group lxdBoundary[LXD Unprivileged Container Boundary]  service hermes(internet)[Hermes Agent v0.17.0]
    service deepseek(cloud)[DeepSeek API]
    service openrouter(cloud)[OpenRouter API]
    service telegram(cloud)[Telegram Bot API]
    service github(cloud)[GitHub API]

    service secretsFile(disk)[Local Secrets Store]
    service sessionDB(disk)[Session Database]
    service agentMemory(disk)[Agent Memory]

    service ufw(internet)[UFW Firewall]
    service fail2ban(internet)[Fail2Ban]

    service personaFA(server)[Persona: Financial Analyst]
    service personaRA(server)[Persona: Research Analyst]
    service personaDev(server)[Persona: Dev]
    service personaOM(server)[Persona: Operations Manager]

    hostBoundary -- container
    lxdBoundary -- hermes
    hermes -- deepseek
    hermes -- openrouter
    hermes -- telegram
    hermes -- github
    hermes -- sessionDB
    hermes -- agentMemory
    deepseek -- secretsFile
    openrouter -- secretsFile
    telegram -- secretsFile
    github -- secretsFile
    hermes -- personaFA
    hermes -- personaRA
    hermes -- personaDev
    hermes -- personaOM
    ufw -- hostBoundary
    fail2ban -- hostBoundary
```

---

## Flow Diagram

```mermaid
sequenceDiagram
    actor User as Telegram User
    participant Telegram as Telegram Bot API
    participant Hermes as Hermes Agent
    participant Skills as Skills & Tools
    participant Persona as Specialist Persona
    participant DeepSeek as DeepSeek API
    participant OpenRouter as OpenRouter (Fallback)
    participant GitHub as GitHub API
    participant Secrets as Local Secrets Store

    User->>Telegram: Send message
    Telegram->>Hermes: Webhook / poll (Bot Token auth)
    Hermes->>Skills: Load relevant skill definitions
    Hermes->>Secrets: Read GitHub PAT (outbound)
    Hermes->>Persona: Select & delegate (if multi-domain)

    alt Primary provider
        Hermes->>DeepSeek: LLM inference (API Key auth)
        DeepSeek-->>Hermes: Response
    else Fallback
        Hermes->>OpenRouter: LLM inference (API Key auth)
        OpenRouter-->>Hermes: Response
    end

    alt Git operation needed
        Hermes->>GitHub: Clone / push / PR (PAT auth)
        GitHub-->>Hermes: Result
    end

    Hermes-->>Telegram: Response message
    Telegram-->>User: Deliver message
```

---

## Trust Boundary Map

```mermaid
graph TB
    subgraph Internet["Internet / External"]
        DeepSeek["🔵 DeepSeek API\ndeepseek-v4-flash"]
        OpenRouter["🔵 OpenRouter API\ngoogle/gemini-2.0-flash"]
        Telegram["🔵 Telegram Bot API"]
        GitHub["🔵 GitHub API\ngithub.com"]
    end

    subgraph HC["🏁 Host Boundary — Oracle Cloud VPS\nUbuntu 24.04 LTS | 2 vCPU | 8 GB RAM | 40 GB disk"]
        UFW["🛡️ UFW Firewall\nInbound: SSH only\nOutbound: Allowed"]
        Fail2Ban["🛡️ Fail2Ban\nSSH brute-force\n5 attempts → ban"]
        
        subgraph LXC["🏁 LXD Unprivileged Container Boundary\nDebian 12 Bookworm | UID remapped | Outbound-only network"]
            Hermes["⚙️ Hermes Agent v0.17.0\nPID 1"]
            
            subgraph Runtime["Runtime Storage"]
                SessionDB["💾 Session Database\nConversation history"]
                AgentMem["💾 Agent Memory\nMEMORY.md / USER.md\nPersona memories"]
            end
            
            subgraph Personas["Specialist Personas"]
                FA["📊 Financial Analyst"]
                RA["🔬 Research Analyst"]
                Dev["💻 Dev"]
                OM["📋 Operations Manager"]
            end
        end
    end
    
    subgraph Secrets["🔑 Secret Locations"]
        SecretFile["📄 ~/.config/hermes/secrets.env\nMode 600 | GitHub PAT only"]
        ConfigFile["📄 ~/.hermes/config.yaml\nTelegram bot token\nProvider API keys\n(redacted in logs)"]
    end

    Hermes -->|"HTTPS (outbound)"| DeepSeek
    Hermes -->|"HTTPS (outbound)"| OpenRouter
    Hermes -->|"HTTPS (outbound)"| Telegram
    Hermes -->|"HTTPS (outbound)"| GitHub
    Hermes --> SessionDB
    Hermes --> AgentMem
    Hermes --> FA
    Hermes --> RA
    Hermes --> Dev
    Hermes --> OM
    Hermes -.->|"source secrets.env"| SecretFile
    Hermes -.->|"config load"| ConfigFile
    UFW -->|"protects"| LXC
    Fail2Ban -->|"protects"| UFW
    DeepSeek -.->|"API Key from env"| SecretFile
    GitHub -.->|"PAT from env"| SecretFile
    Telegram -.->|"Bot token in config"| ConfigFile
```
