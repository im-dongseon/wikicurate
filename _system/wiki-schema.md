# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## 역할

이 저장소는 **LLM이 작성·유지하는 개인 지식 베이스(위키)**다. 너는 사서이자 편집자다. 사용자는 소스를 가져오고 질문하며, 너는 위키를 작성하고 갱신한다.

---

## 디렉토리 구조

```
/
├── raw/                # 원본 소스 (불변 — 읽기 전용)
│   └── assets/         # 로컬 이미지·첨부파일
├── wiki/               # LLM이 작성·관리하는 마크다운 파일
│   ├── index.md        # 모든 위키 페이지 카탈로그
│   ├── log.md          # 작업 이력 (append-only)
│   ├── sources/        # 소스별 요약 페이지 (ingest 결과)
│   ├── entities/       # 인물·조직·제품 등 고유 항목
│   ├── concepts/       # 개념·주제 페이지
│   └── analyses/       # 질의 결과·비교·분석 페이지
└── graphify-out/       # graphify 생성물 (자동 생성, git 제외)
    └── graph.json      # wiki 페이지 관계 그래프
```

> 디렉토리가 아직 없으면 작업 시작 전에 생성한다. 새 wiki 페이지는 반드시 위 4개 카테고리 폴더 중 하나에 저장한다.

---

## 위키 페이지 형식

```markdown
---
title: 페이지 제목
tags: [태그1, 태그2]
sources: [raw/파일명.md]
updated: YYYY-MM-DD
---

본문…

## 관련 항목
- [[다른 페이지]]
```

- 링크는 `[[페이지 제목]]` (Obsidian 내부 링크) 형식
- **파일명은 `[[링크 텍스트]]` 및 `title:` 프론트매터와 완전히 일치**시킨다 (공백·특수문자 포함). 슬러그형(압축형) 파일명 사용 금지.
  - 올바른 예: `LLM 위키.md` ↔ `[[LLM 위키]]` ↔ `title: LLM 위키`
  - 잘못된 예: `LLM위키.md`, `llm-wiki.md`, `그래프DB-지식그래프.md`
- 헤딩은 H2부터 사용 (H1은 title 프론트매터로 대체)
- 카테고리: `entities/`, `concepts/`, `sources/`, `analyses/` 하위 폴더로 구분

---

## 작업 흐름

세 가지 작업은 슬래시 커맨드로 실행한다. 상세 절차는 `.claude/commands/` 참고.

| 커맨드 | 용도 | 예시 |
|---|---|---|
| `/ingest` | 새 소스를 wiki에 통합 | `/ingest raw/article.md` |
| `/query` | wiki 기반 질의·분석 | `/query 경쟁사 A와 B의 차이점은?` |
| `/lint` | wiki 건강 점검 및 정리 | `/lint` |

---

## index.md 규칙

각 항목 형식:
```
- [[페이지 제목]] — 한 줄 요약 (소스 N개)
```

카테고리별로 섹션 구분. 모든 ingest·신규 페이지 생성 시 반드시 갱신.

## log.md 규칙

- append-only — 기존 항목 수정 금지
- 접두사 형식: `## [YYYY-MM-DD] {ingest|query|lint} | 제목`
- 최신 항목이 파일 끝에 위치

---

## 지식 그래프 (graphify)

`graphify-out/graph.json`에 wiki 페이지 간 관계를 사전 계산해 저장한다.

- **빌드**: ingest·lint 완료 후 `/graphify --update` 절차에 따라 Claude가 직접 파일을 읽고 graph.json을 생성
- **활용**: `/query`에서 1-hop 관련 페이지 탐색, `/lint`에서 고아 페이지·끊긴 링크 감지
- **신선도**: `meta.built_at` 기준 24시간 초과 시 재빌드 제안
- **폴백**: graph.json 없거나 오래됐으면 `wiki/index.md`로 대체

---

## 파일 편집 도구 우선순위

위키 파일을 생성·수정할 때:

1. **Obsidian CLI** (`obsidian` 명령) — Obsidian vault와 연동된 경우 우선 사용
2. **OS 기본 명령어** — alias 우회를 위해 아래 규칙을 따른다.

**텍스트 처리** (`cat`, `grep`, `find`, `sed`, `awk` 등): `\` 접두사로 호출한다.
```bash
\cat file.md
\grep "pattern" wiki/
\find wiki/ -name "*.md"
```
> `bat`, color-grep 등 alias로 인한 라인 넘버·색상 코드 오염을 방지한다.

**파일 조작** (`cp`, `mv`, `rsync` 등): `\` 접두사를 사용한다.
```bash
\cp source.md wiki/sources/
\rsync -av wiki/ "$TARGET/wiki/"
```

---

## Universal Tool Mapping

To ensure compatibility across different AI agents, map the following conceptual tools to your environment's specific tools:

| Conceptual Tool | Equivalent Tools (e.g., Gemini / Claude / GPT) |
|:---|:---|
| **READ** | `read_file`, `cat`, `\cat` |
| **EDIT** | `replace`, `write_file`, `sed`, `EDIT` |
| **BASH** | `run_shell_command`, `bash`, `shell` |
| **SEARCH** | `grep_search`, `grep`, `find` |
| **ASK** | `ask_user`, `input`, `prompt` |

## Command Execution Protocol

If your environment does not support slash commands (e.g., `/ingest`):
1. Locate the playbook in `_system/commands/[command_name].md`.
2. Read the defined steps.
3. Execute the workflow using your available tools.

---

## 바이너리·비텍스트 소스 처리

`raw/`에 `.md` 이외의 파일이 있을 때 형식별 변환 절차를 따른다.

### PDF

`pdftotext` (poppler)로 텍스트를 추출해 wiki 페이지 작성에 직접 활용한다. **`raw/`에 중간 `.md` 파일을 저장하지 않는다.**

```bash
/opt/homebrew/bin/pdftotext -layout "raw/파일명.pdf" -
```

- Read 도구는 poppler PATH를 인식하지 못하므로 Bash 도구로 full path 지정 필수
- poppler 미설치 시: `brew install poppler`
- `sources:` 프론트매터에 원본 `.pdf` 경로를 기록한다: `sources: [raw/파일명.pdf]`

### PPTX

python-pptx로 슬라이드별 텍스트를 추출해 `raw/<이름>.md`로 저장한 뒤, 해당 `.md`를 ingest한다.

```python
from pptx import Presentation
prs = Presentation("raw/파일명.pptx")
for i, slide in enumerate(prs.slides, 1):
    texts = [shape.text_frame.text for shape in slide.shapes if shape.has_text_frame]
```

- python-pptx 미설치 시: `pip3 install python-pptx`
- `sources:` 프론트매터에 원본 `.pptx` 경로를 기록한다: `sources: [raw/파일명.pptx]`

### XLSX

openpyxl로 시트 데이터를 마크다운 테이블로 변환해 `raw/<이름>.md`로 저장한 뒤, 해당 `.md`를 ingest한다.

```python
import openpyxl
wb = openpyxl.load_workbook("raw/파일명.xlsx")
# 각 시트를 마크다운 테이블로 변환
```

- openpyxl 미설치 시: `pip3 install openpyxl`
- `sources:` 프론트매터에 원본 `.xlsx` 경로를 기록한다: `sources: [raw/파일명.xlsx]`

### log.md 기록 규칙

변환 중간 파일이 있더라도 **원본 바이너리 파일명**으로 기록한다.

```
## [날짜] ingest | 파일명.pptx
## [날짜] ingest | 파일명.xlsx
## [날짜] ingest | 파일명.pdf
```

---

## 핵심 원칙

- `raw/` 파일은 절대 수정하지 않는다.
- 모든 위키 페이지에는 프론트매터를 포함한다.
- **파일명 = `title:` 프론트매터 = `[[링크 텍스트]]`** — 셋이 항상 동일해야 한다. 불일치 시 Obsidian이 0B 파일을 생성한다.
- 소스 하나를 처리할 때 관련 페이지를 한 번에 일괄 갱신한다 (세션을 나누지 않는다).
- 새 정보가 기존 클레임과 충돌하면 해당 페이지에 명시적으로 표기한다.
