<!-- Thanks to: Andrej Karpathy, Louis Wang -->

<div align="center">

# WikiCurate v0.2.0

Autonomous LLM Wiki managed by AI agents.

**AI 에이전트가 관리하는 자율형 LLM 위키 시스템**

[![Obsidian](https://img.shields.io/badge/Obsidian-Vault-7C3AED?logo=obsidian&logoColor=white)](https://obsidian.md/)
[![Version](https://img.shields.io/badge/Version-0.2.0-blue)](releases/CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

<br/>

[**`한국어`**](README.md) · **`English`**

</div>

---

## Table of Contents

- [What is WikiCurate?](#what-is-wikicurate)
- [Core Architecture (3-Layer Model)](#core-architecture-3-layer-model)
- [Key Features & Commands](#key-features--commands)
- [Universal Agent Compatibility](#universal-agent-compatibility)
- [Quick Start](#quick-start)
- [Directory Structure](#directory-structure)
- [License](#license)

---

## What is WikiCurate?

`WikiCurate` is an autonomous knowledge management system where AI agents automatically organize and connect your information.

### Why do you need it?

- Prevents countless notes and web scraps from becoming a **knowledge graveyard**.
- AI agents (Claude Code, Gemini CLI, etc.) act as your **Librarians** to classify knowledge, remove duplicates, and automatically derive new insights.

---

## Core Architecture (3-Layer Model)

The system consists of three distinct layers:

1.  **Raw Layer (`raw/`) — Immutable Source**: Stores raw data collected by the user. Agents perform read-only operations.
2.  **Wiki Layer (`wiki/`) — Evolving Knowledge**: A structured markdown knowledge network built by processing raw sources. Agents have full ownership over its structure and naming.
3.  **Schema Layer (`_system/`) — Unified Guidance**: Contains the system's Code of Conduct (`wiki-schema.md`) and task-specific playbooks (`commands/`).

---

## Key Features & Commands

The system is operated via slash commands defined in the playbooks.

| Command | Feature | Description |
| :--- | :--- | :--- |
| `/ingest` | Source Ingest | Analyzes new files in `raw/`, creates wiki pages, and integrates with existing knowledge. |
| `/query` | Intelligent Query | Explores the knowledge graph to generate context-based answers and save analyses. |
| `/lint` | Health Check | Detects orphan pages, repairs broken links, and resolves contradictions. |
| `/graphify` | Graph Build | Analyzes relationships between wiki pages to generate `graph.json`. |
| `/setup` | Environment Setup | Creates initial folder structure and verifies required tool installations. |

### Auto Ingest (v0.2.0)

Automatically runs `/ingest` within 10 minutes whenever a file is added or modified in `raw/`.
Registered as a macOS launchd agent during `deploy.sh`, and can also be managed independently.

```bash
./scripts/watcher.sh register    # Register
./scripts/watcher.sh unregister  # Unregister
./scripts/watcher.sh status      # Check status
./scripts/watcher.sh log         # Stream execution log
```

Common log filters:

```bash
./scripts/watcher.sh log                        # Live streaming (Ctrl+C to exit)
grep "완료" /tmp/wikicurate-watcher.log         # Ingest run summaries only
grep "FAIL" /tmp/wikicurate-watcher.log         # Failed files only
tail -100 /tmp/wikicurate-watcher.log           # Last 100 lines
```

---

## Universal Agent Compatibility

`WikiCurate v0.2.0` is platform-agnostic.
- **Tool Mapping:** Designed to automatically recognize tools (READ, EDIT, BASH, etc.) in various agent environments.
- **Universal Entry Points:** `CLAUDE.md` and `AGENTS.md` allow any agent to immediately understand the system's guidelines.

---

## Quick Start

### Step 1. Environment Setup
Clone the repository and create a `.env` file in the root directory to set your Obsidian vault path.
```bash
# .env file
DEPLOY_PATHS=(
  "/Users/yourname/Documents/my-vault"
)
```

### Step 2. System Deployment
Run the deployment script to inject system files, commands, and auto-register the ingest watcher.
```bash
./deploy.sh
# → Deploys _system/ + auto-registers launchd ingest-watcher
```

### Step 3. Initialization & Operation
Launch your agent in the vault directory and give the following command:
```bash
/setup
# After this, dropping files into raw/ will trigger ingest automatically within 10 minutes.
```

---

## Directory Structure

```
wikicurate/             # Development zone (this repository)
├── scripts/            # Automation scripts
│   ├── watch-ingest.sh # fswatch-based auto ingest watcher
│   └── watcher.sh      # launchd register/unregister/status
├── _system/            # System engine (Schema, Commands)
├── deploy.sh           # Deploy + auto-register watcher
└── .env                # DEPLOY_PATHS configuration

vault/                  # Operations zone (deployment target, KMS root)
├── raw/                # Raw source data (PDF, Images, Web clips)
├── wiki/               # Agent-managed knowledge (Index, Log, Sources...)
├── _system/            # System engine (deployed)
├── .claude/            # Agent settings (Symlinks to commands)
├── CLAUDE.md           # Agent entry point 1
└── AGENTS.md           # Agent entry point 2
```

---

## References & Tech Stack

### Core Concepts
- **[LLM Wiki Pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f):** The core design pattern for AI agents to accumulate and structure knowledge.

### Tools & Libraries
- **[Obsidian](https://obsidian.md/):** Knowledge management tool for visualization and editing.
- **[graphify](https://github.com/safishamsi/graphify):** Core command for analyzing relationships and visualizing the knowledge graph.
- **AI Agents:** Compatible with universal AI agents like [Gemini CLI](https://github.com/google/gemini-cli) and [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code).

---

## License

[MIT License](LICENSE)

---

<div align="center">

Developed by **WikiCurate Team**.

</div>
