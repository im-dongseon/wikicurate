<!-- Thanks to: Andrej Karpathy, Louis Wang -->

<div align="center">

# WikiCurate v0.2.5

AI 에이전트가 관리하는 자율형 LLM 위키 시스템

**Autonomous LLM Wiki managed by AI agents.**

[![Obsidian](https://img.shields.io/badge/Obsidian-Vault-7C3AED?logo=obsidian&logoColor=white)](https://obsidian.md/)
[![Version](https://img.shields.io/badge/Version-0.2.5-blue)](releases/CHANGELOG.md)
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

### 자동 ingest + lint + 재시도 (v0.2.3)

`raw/`에 파일을 추가하거나 수정하면 10분 이내에 자동으로 `/ingest`가 실행되고,
ingest 성공 후 `/lint`가 자동으로 이어서 실행됩니다.
실패한 파일은 SQLite DB에 기록되어 다음 주기에 자동 재시도(최대 5회)되며,
5회 모두 실패 시 `raw/error/`로 격리됩니다.
[`deploy.sh`](deploy.sh) 실행 시 macOS launchd에 자동 등록되며, 별도 관리도 가능합니다.

```bash
./scripts/watcher.sh register    # 등록
./scripts/watcher.sh unregister  # 해제
./scripts/watcher.sh status      # 상태 확인
./scripts/watcher.sh log         # 실행 로그 실시간 확인
```

로그에서 자주 쓰는 필터:

```bash
./scripts/watcher.sh log                        # 실시간 스트리밍 (Ctrl+C 종료)
grep "완료" /tmp/wikicurate-watcher.log         # ingest 실행 요약만
grep "FAIL" /tmp/wikicurate-watcher.log         # 실패 항목만
grep "RETRY" /tmp/wikicurate-watcher.log        # 재시도 항목만
grep "ISOLATED" /tmp/wikicurate-watcher.log     # 격리된 항목만
tail -100 /tmp/wikicurate-watcher.log           # 최근 100줄
```

---

## 범용 에이전트 호환성

`WikiCurate v0.2.5`은 특정 플랫폼에 종속되지 않습니다.
- **도구 매핑 (Tool Mapping):** 각 에이전트 환경의 도구(READ, EDIT, BASH 등)를 자동으로 인식하도록 설계되었습니다.
- **범용 진입점:** `CLAUDE.md`, `AGENTS.md`를 통해 어떤 에이전트라도 즉시 시스템 지침을 이해할 수 있습니다.

---

## 빠른 시작

### Step 1. 환경 설정
레포지토리를 클론한 후 `.env` 파일을 생성하고 옵시디언 볼트 경로를 설정합니다.
```bash
# .env 파일
WIKICURATE_AGENT=codex
DEPLOY_PATHS=(
  "/Users/yourname/Documents/my-vault"
)
```

### Step 2. 시스템 배포
배포 스크립트를 실행하여 시스템 파일과 명령어를 볼트에 주입하고, ingest-watcher를 자동 등록합니다.
기본 자동 실행기는 `codex`이며, 필요하면 `.env` 또는 셸 환경에서 `WIKICURATE_AGENT`로 바꿀 수 있습니다.
```bash
./deploy.sh
# → _system/ 배포 + launchd ingest-watcher 자동 등록
```

배포된 버전 확인:
```bash
cat vault/_system/VERSION
```

### Step 3. 초기 설정 및 운영
볼트 디렉토리에서 에이전트를 실행하고 다음 명령을 내립니다.
```bash
/setup
# Python 의존성 설치, 환경 검증 수행
# .gsheet/.gdoc/.gslides 처리가 필요한 경우 Google 연동 설정(선택)도 안내됩니다.
# 이후 raw/에 파일을 추가하면 10분 이내 자동 ingest 실행
```

---

## 디렉토리 구조

```
wikicurate/             # 개발 존 (이 저장소)
├── scripts/            # 자동화 스크립트
│   ├── watch-ingest.sh # fswatch 기반 자동 ingest 감시
│   └── watcher.sh      # launchd 등록/해제/상태 관리
├── _system/            # 시스템 엔진 (Schema, Commands)
├── deploy.sh           # 배포 + watcher 자동 등록
└── .env                # DEPLOY_PATHS 설정

vault/                  # 운영 존 (배포 대상, KMS 루트)
├── raw/                # 원본 데이터 (PDF, 이미지, 웹 클립)
│   └── error/          # ingest 최종 실패 파일 격리 폴더
├── wiki/               # 에이전트 관리 지식 (Index, Log, Sources...)
├── _system/            # 시스템 엔진 (배포됨)
├── _state/             # 런타임 상태 (재시도 DB 등, 자동 생성)
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
- **AI Agents:** [Codex CLI](https://developers.openai.com/codex/cli), [Gemini CLI](https://github.com/google/gemini-cli), [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code) 등 범용 AI 에이전트와 호환됩니다.

---

## 라이선스

[MIT License](LICENSE)

---

<div align="center">

Developed by **WikiCurate Team**.

</div>
