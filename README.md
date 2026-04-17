<!-- Thanks to: Andrej Karpathy, Louis Wang -->

<div align="center">

# WikiCurate v0.1.0

AI 에이전트가 관리하는 자율형 LLM 위키 시스템

**Autonomous LLM Wiki managed by AI agents.**

[![Obsidian](https://img.shields.io/badge/Obsidian-Vault-7C3AED?logo=obsidian&logoColor=white)](https://obsidian.md/)
[![Version](https://img.shields.io/badge/Version-0.1.0-blue)](releases/CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

<br/>

**`한국어`** · [**`English`**](README.en.md)

</div>

---

## 목차

- [WikiCurate란?](#wikicurate란)
- [핵심 아키텍처 (3-Layer Model)](#핵심-아키텍처-3-layer-model)
- [주요 기능 및 명령](#주요-기능-및-명령)
- [범용 에이전트 호환성](#범용-에이전트-호환성)
- [빠른 시작](#빠른-시작)
- [디렉토리 구조](#디렉토리-구조)
- [개발 방법론](#개발-방법론)
- [라이선스](#라이선스)

---

## WikiCurate란?

`WikiCurate`는 AI 에이전트가 지식을 스스로 분류하고 연결하는 자율형 지식 관리 시스템입니다.

### 왜 필요한가?

- 수많은 메모와 웹 스크랩이 결국 **지식의 공동묘지**가 되는 것을 방지합니다.
- AI 에이전트(Claude Code, Gemini CLI 등)가 당신의 **사서(Librarian)** 가 되어 지식을 분류하고, 중복을 제거하며, 새로운 통찰을 자동으로 도출합니다.

---

## 핵심 아키텍처 (3-Layer Model)

시스템은 역할이 명확히 분리된 3개의 레이어로 구성됩니다.

1.  **Raw Layer (`raw/`) — 불변의 소스**: 사용자가 수집한 원본 데이터 보관. 에이전트는 읽기만 수행합니다.
2.  **Wiki Layer (`wiki/`) — 진화하는 지식**: 에이전트가 원본을 가공하여 구축하는 지식망. 에이전트가 구조와 명명에 대한 전권을 가집니다.
3.  **Schema Layer (`_system/`) — 통합 지침**: 에이전트의 행동 강령(`wiki-schema.md`)과 작업별 플레이북(`commands/`)이 포함됩니다.

---

## 주요 기능 및 명령

플레이북에 정의된 슬래시 커맨드를 통해 시스템을 운영합니다.

| 명령 | 기능 | 설명 |
| :--- | :--- | :--- |
| `/ingest` | 소스 수집 | `raw/`의 신규 파일을 분석하여 위키 페이지 생성 및 기존 지식 통합 |
| `/query` | 지능형 질의 | 지식 그래프를 탐색하여 맥락 기반 답변 생성 및 분석 저장 |
| `/lint` | 건강 점검 | 고아 페이지 탐지, 끊긴 링크 복구, 지식 간 모순 해결 |
| `/graphify` | 그래프 빌드 | 위키 페이지 간의 관계를 분석하여 `graph.json` 생성 |
| `/setup` | 환경 구축 | 초기 폴더 구조 생성 및 필요한 도구 설치 확인 |

---

## 범용 에이전트 호환성

`WikiCurate v0.1.0`은 특정 플랫폼에 종속되지 않습니다.
- **도구 매핑 (Tool Mapping):** 각 에이전트 환경의 도구(READ, EDIT, BASH 등)를 자동으로 인식하도록 설계되었습니다.
- **범용 진입점:** `CLAUDE.md`, `AGENTS.md`를 통해 어떤 에이전트라도 즉시 시스템 지침을 이해할 수 있습니다.

---

## 빠른 시작

### Step 1. 환경 설정
레포지토리를 클론한 후 `.env` 파일을 생성하고 옵시디언 볼트 경로를 설정합니다.
```bash
# .env 파일
DEPLOY_PATHS=(
  "/Users/yourname/Documents/my-vault"
)
```

### Step 2. 시스템 배포
배포 스크립트를 실행하여 시스템 파일과 명령어를 볼트에 주입합니다.
```bash
./deploy.sh
```

### Step 3. 초기 설정 및 운영
볼트 디렉토리에서 에이전트를 실행하고 다음 명령을 내립니다.
```bash
/setup
/ingest
```

---

## 디렉토리 구조

```
vault/
├── raw/                # 원본 데이터 (PDF, 이미지, 웹 클립)
├── wiki/               # 에이전트 관리 지식 (Index, Log, Sources...)
├── _system/            # 시스템 엔진 (Schema, Commands)
├── .claude/            # 에이전트 전용 설정 (Commands 심볼릭 링크)
├── CLAUDE.md           # 에이전트 진입점 1
└── AGENTS.md           # 에이전트 진입점 2
```

---

## 참고 자료 및 기술 스택

### 핵심 개념
- **[LLM Wiki Pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f):** AI 에이전트가 지식을 축적하고 구조화하는 핵심 설계 패턴입니다.

### 사용된 도구 및 라이브러리
- **[Obsidian](https://obsidian.md/):** 지식 베이스 시각화 및 편집을 위한 지식 관리 도구.
- **[graphify](https://github.com/safishamsi/graphify):** 위키 페이지 간의 관계를 분석하여 지식 그래프를 시각화하는 핵심 명령.
- **AI Agents:** [Gemini CLI](https://github.com/google/gemini-cli), [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code) 등 범용 AI 에이전트와 호환됩니다.

---

## 라이선스

[MIT License](LICENSE)

---

<div align="center">

Developed by **WikiCurate Team**.

</div>
