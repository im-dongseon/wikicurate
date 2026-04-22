<!-- Thanks to: Andrej Karpathy, Louis Wang -->

<div align="center">

# WikiCurate v0.2.6

Autonomous LLM Wiki managed by AI agents.

**AI 에이전트가 관리하는 자율형 LLM 위키 시스템**

[![Obsidian](https://img.shields.io/badge/Obsidian-Vault-7C3AED?logo=obsidian&logoColor=white)](https://obsidian.md/)
[![Version](https://img.shields.io/badge/Version-0.2.6-blue)](releases/CHANGELOG.md)
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
| `/graphify` | Graph Build | Generates `graph.json` + `GRAPH_REPORT.md` via the graphifyy CLI. |
| `/setup` | Environment Setup | Creates initial folder structure and verifies required tool installations. |

### Auto Ingest → Lint → Graphify (v0.2.6)

Drop a file into `wiki-inbox/` and `/ingest` runs automatically within 10 minutes.
After a successful ingest, `/lint` runs, followed by `graphify update .` to keep the knowledge graph current.
Failed files are recorded in a SQLite DB and retried automatically (up to 5 times).
After 5 consecutive failures, the file is isolated to `wiki-inbox/error/`.
Registered as a macOS launchd agent during `deploy.sh`.

```bash
./scripts/watcher.sh register    # Register (ingest-watcher + daily-rescan)
./scripts/watcher.sh unregister  # Unregister
./scripts/watcher.sh status      # Check status
./scripts/watcher.sh log         # Stream ingest log
./scripts/watcher.sh rescan-log  # Stream daily rescan log
```

### Daily Google Stub Rescan (v0.2.6)

`.gdoc` / `.gsheet` / `.gslides` files are local stubs — fswatch cannot detect when their remote content changes.
`daily-rescan.sh` runs automatically at 07/10/13/16/19/21h every day to re-ingest stubs and recover any unprocessed files left in `raw/`.

---

## Universal Agent Compatibility

`WikiCurate v0.2.6` is platform-agnostic.
- **Tool Mapping:** Designed to automatically recognize tools (READ, EDIT, BASH, etc.) in various agent environments.
- **Universal Entry Points:** `CLAUDE.md` and `AGENTS.md` allow any agent to immediately understand the system's guidelines.

---

## Quick Start

### Step 1. Environment Setup
Clone the repository and run the deployment script — an interactive wizard will guide you through vault path and agent configuration.
```bash
./deploy.sh --setup
# Runs the wikicurate.yaml setup wizard
```

Or edit directly:
```yaml
# wikicurate.yaml
wikis:
  - deploy: "/Users/yourname/Documents/my-vault"
agent: codex
interval: 600
```

### Step 2. System Deployment
Run the deployment script to inject system files and auto-register both the ingest-watcher and daily-rescan jobs.
```bash
./deploy.sh
# → Deploys _system/ + auto-registers launchd ingest-watcher + daily-rescan
```

Check the deployed version:
```bash
cat vault/_system/VERSION
```

### Step 3. Initialization & Operation
Launch your agent in the vault directory and give the following command:
```bash
/setup
# Installs Python dependencies and validates the environment.
# If you need to process .gsheet/.gdoc/.gslides files, Google integration setup (optional) is also guided.
# After this, dropping files into raw/ will trigger ingest automatically within 10 minutes.
```

---

## Directory Structure

```
wikicurate/             # Development zone (this repository)
├── scripts/
│   ├── watch-ingest.sh # fswatch-based auto ingest watcher
│   ├── daily-rescan.sh # Daily Google stub rescan (07~21h, 6x/day)
│   └── watcher.sh      # launchd register/unregister/status
├── _system/            # System engine (Schema, Commands)
├── deploy.sh           # Deploy + auto-register watcher
└── wikicurate.yaml     # Vault paths and agent configuration

vault/                  # Operations zone (deployment target, KMS root)
├── wiki-inbox/         # File drop zone (moved to raw/ after processing)
│   └── error/          # Files isolated after repeated failures
├── raw/                # Immutable source archive
├── wiki/               # Agent-managed knowledge (Index, Log, Sources...)
├── graphify-out/       # Knowledge graph artifacts (auto-generated)
├── _system/            # System engine (deployed)
├── _state/             # Runtime state (retry DB, auto-created)
├── .claude/            # Claude Code settings (PreToolUse hook included)
├── CLAUDE.md           # Agent entry point (Claude)
├── AGENTS.md           # Agent entry point (Codex)
└── GEMINI.md           # Agent entry point (Gemini)
```

---

## References & Tech Stack

### Core Concepts
- **[LLM Wiki Pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f):** The core design pattern for AI agents to accumulate and structure knowledge.

### Tools & Libraries
- **[Obsidian](https://obsidian.md/):** Knowledge management tool for visualization and editing.
- **[graphify](https://github.com/safishamsi/graphify):** Core command for analyzing relationships and visualizing the knowledge graph.
- **AI Agents:** Compatible with universal AI agents like [Codex CLI](https://developers.openai.com/codex/cli), [Gemini CLI](https://github.com/google/gemini-cli), and [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code).

---

## License

[MIT License](LICENSE)

---

<div align="center">

Developed by **WikiCurate Team**.

</div>
