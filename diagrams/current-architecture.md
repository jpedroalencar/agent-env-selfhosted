# Current Architecture

Mermaid architecture diagram for the self-hosted AI agent platform.

**Note:** This file is a source document for manual SVG export. The canonical editable source is `diagrams/current-architecture.drawio`.

---

## Architecture Overview

```mermaid
flowchart LR
    %% Floating node from your original list
    vps["Oracle Cloud VPS - Ubuntu 24.04 LTS"]

    %% Security & Infrastructure Dependencies
    ufw["UFW Firewall"] --> hostLayer["Host Security Layer"]
    fail2ban["Fail2Ban"] --> hostLayer
    hostLayer --> lxdGroup["LXD Hypervisor"]
    
    %% Backup Flow
    backupGroup["Backup & Recovery"] --> snapshots["LXD Snapshots"]
    backupScript["backup-container.sh"] --> snapshots
    snapshots --> lxdGroup
    
    %% Container Layer
    lxdGroup --> container["Hermes Container - Debian 12 Bookworm"]
    evidence["Host Validation Evidence"] --> container
    container --> hermes["Hermes Agent v0.17.0"]
    
    %% Hermes Internal Storage & Personas
    hermes --> sessionDB["Session Database"]
    hermes --> agentMemory["Agent Memory"]
    hermes --> personaFA["Persona: Financial Analyst"]
    hermes --> personaRA["Persona: Research Analyst"]
    hermes --> personaDev["Persona: Dev"]
    hermes --> personaOM["Persona: Operations Manager"]
    
    %% External API Flow
    hermes --> deepseek["DeepSeek API"]
    hermes --> openrouter["OpenRouter API"]
    hermes --> telegram["Telegram Bot API"]
    hermes --> github["GitHub API"]
    
    %% Secrets Flow
    deepseek --> secretsFile["Local Secrets Store"]
    openrouter --> secretsFile
    telegram --> secretsFile
    github --> secretsFile
```

---

## Flow Diagram

```mermaid
sequenceDiagram
    autonumber

    %% Grouping components into visual boxes
    box transparent 1. User & Trigger
        actor User as Telegram User
        participant Telegram as Telegram Bot API
    end

    box transparent 2. Hermes Internal Processing
        participant Hermes as Hermes Agent
        participant Persona as Specialist Persona
        participant Skills as Skills & Tools
        participant Secrets as Local Secrets Store
    end

    box transparent 3. External Cloud APIs
        participant DeepSeek as DeepSeek API
        participant OpenRouter as OpenRouter
        participant GitHub as GitHub API
    end

    %% Phase 1: Ingestion & Setup
    Note over User,Secrets: Phase 1: Message Ingestion & Strategy
    User->>Telegram: Send message
    Telegram->>Hermes: Webhook / poll (Bot Token auth)
    
    activate Hermes
    Hermes->>Skills: Load relevant skill definitions
    Hermes->>Persona: Select & delegate (if multi-domain)

    %% Phase 2: AI Inference
    Note over Hermes,OpenRouter: Phase 2: LLM Inference
    
    alt Primary provider
        Hermes->>DeepSeek: LLM inference (API Key auth)
        DeepSeek-->>Hermes: Strategy / Response
    else Fallback
        Hermes->>OpenRouter: LLM inference (API Key auth)
        OpenRouter-->>Hermes: Strategy / Response
    end

    %% Phase 3: Tool Execution
    Note over Hermes,GitHub: Phase 3: Tool Execution (Optional)
    
    opt Git operation needed
        Hermes->>Secrets: Read GitHub PAT (outbound)
        Hermes->>GitHub: Clone / push / PR (PAT auth)
        GitHub-->>Hermes: Action Result
    end

    %% Phase 4: Delivery
    Note over User,Hermes: Phase 4: Delivery
    Hermes-->>Telegram: Formatted Response message
    deactivate Hermes
    
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
