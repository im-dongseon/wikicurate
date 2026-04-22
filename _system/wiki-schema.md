# WikiCurate Agent Guide

This file provides guidance to AI agents working with this repository.

---

## 역할

이 저장소는 **LLM이 작성·유지하는 개인 지식 베이스(위키)**다. 너는 사서이자 편집자다. 사용자는 소스를 가져오고 질문하며, 너는 위키를 작성하고 갱신한다.

---

## 디렉토리 구조

```
/
├── wiki-inbox/         # 신규 소스 투입 드롭존 (처리 후 raw/로 이동됨)
│   └── error/          # 반복 실패 격리 (수동 처리 필요)
├── raw/                # 원본 소스 아카이브 (불변 — 읽기 전용)
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

세 가지 작업은 슬래시 커맨드 또는 playbook 실행으로 처리한다. 상세 절차는 `_system/commands/` 참고.

| 커맨드 | 용도 | 예시 |
|---|---|---|
| `/ingest` | 새 소스를 wiki에 통합 | `/ingest` (wiki-inbox/ 자동 스캔) |
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

`graphify-out/graph.json`과 `graphify-out/GRAPH_REPORT.md`에 wiki 지식 그래프를 사전 계산해 저장한다.

- **빌드**: ingest+lint 완료 후 `watch-ingest.sh`가 자동으로 `graphify update .`를 실행해 graph.json과 GRAPH_REPORT.md를 생성한다. 수동 실행: `/graphify`
- **활용**: `/query`에서 GRAPH_REPORT.md + graph.json 기반 탐색, `/lint`에서 graph.json 기반 고아 페이지·끊긴 링크 감지
- **폴백**: graph.json / GRAPH_REPORT.md 없으면 `wiki/index.md`로 대체

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

openpyxl로 **시트명 + 컬럼 헤더 + 행 수(추정치)만** 추출해 wiki 페이지를 직접 작성한다. **`raw/`에 중간 `.md` 파일을 저장하지 않는다.**

```python
import openpyxl
wb = openpyxl.load_workbook("raw/파일명.xlsx", read_only=True, data_only=True)
for ws in wb.worksheets:
    # 첫 번째 비어있지 않은 행을 헤더로 채택 (최대 5행 탐색)
    headers = []
    header_row = None
    for i, row in enumerate(ws.iter_rows(max_row=5, values_only=True), start=1):
        non_empty = [v for v in row if v is not None and str(v).strip()]
        if non_empty:
            headers = [str(v) if v is not None else "" for v in row]
            header_row = i
            break
    if not headers:
        row_count = 0  # 빈 시트 또는 구조 불명확
    else:
        row_count = (ws.max_row or header_row) - header_row
    # → 시트명, headers, row_count(추정치)만 wiki에 기록
```

- `ws.max_row`는 서식만 지정된 빈 행을 포함할 수 있으므로 wiki에 "추정치"로 표기한다.
- openpyxl 미설치 시: `pip3 install openpyxl`
- `sources:` 프론트매터에 원본 `.xlsx` 경로를 기록한다: `sources: [raw/파일명.xlsx]`

### CSV / TSV

구분자가 다를 뿐 구조가 동일하므로 통합 처리한다. 파이썬 내장 `csv` 모듈로 파싱하며 **`raw/`에 중간 파일을 저장하지 않는다.**

**추출 대상 (토큰 절약):** 파일명 + 구분자 종류 + 컬럼 헤더 + 총 행 수

```python
import csv

file_path = "raw/파일명.csv"  # .tsv도 동일 절차

# 구분자 자동 감지
with open(file_path, newline="", encoding="utf-8-sig") as f:
    sample = f.read(4096)

try:
    dialect = csv.Sniffer().sniff(sample, delimiters=",\t|;")
    delimiter = dialect.delimiter
except csv.Error:
    # 감지 실패 시 확장자 기반 기본값 적용
    delimiter = "\t" if file_path.endswith(".tsv") else ","

# 헤더 및 행 수 추출 (제너레이터로 메모리 절약)
with open(file_path, newline="", encoding="utf-8-sig") as f:
    reader = csv.reader(f, delimiter=delimiter)
    headers = next(reader, [])
    row_count = sum(1 for _ in reader)

delimiter_name = "탭(TSV)" if delimiter == "\t" else f'"{delimiter}"'
# → file_path, delimiter_name, headers, row_count를 wiki에 기록
```

- 인코딩: UTF-8(BOM 포함 대응) 우선. 실패 시 `cp949`로 재시도한다.
  ```python
  try:
      # UTF-8 시도 (위 코드)
      ...
  except UnicodeDecodeError:
      with open(file_path, newline="", encoding="cp949") as f:
          ...
  ```
- 헤더 행이 없는 파일은 `headers: []`로 표기하고 row_count는 전체 행 수로 기록한다.
- `sources:` 프론트매터에 원본 경로를 기록한다: `sources: [raw/파일명.csv]`

### DOCX

`python-docx`로 단락 구조를 추출해 wiki 페이지를 직접 작성한다. **`raw/`에 중간 파일을 저장하지 않는다.**

**추출 대상 (토큰 절약):** 문서 제목 + 헤딩 구조 + 각 섹션 첫 단락(200자 이내) + 표 개수

```python
from docx import Document

doc = Document("raw/파일명.docx")

# 제목: core_properties 우선, 없으면 "Title" 스타일 단락
title = doc.core_properties.title or ""
sections = []
got_first_para = False

for para in doc.paragraphs:
    style = para.style.name
    text = para.text.strip()
    if not text:
        continue
    # 영문("Heading 1") 및 한국어("제목 1") 스타일 모두 대응
    is_heading = style.startswith("Heading") or style.startswith("제목")
    is_normal = style in ("Normal", "본문")
    if not title and style == "Title":
        title = text
        continue
    if is_heading:
        sections.append({"heading": text, "style": style, "first_para": None})
        got_first_para = False
    elif is_normal and not got_first_para and sections:
        sections[-1]["first_para"] = text[:200]
        got_first_para = True

table_count = len(doc.tables)
# → title, sections(heading + first_para), table_count를 wiki에 기록
```

- 커스텀 스타일 사용 시 헤딩이 감지되지 않을 수 있다. 표준 스타일(Heading 1~6 / 제목 1~6) 사용을 권장한다.
- python-docx 미설치 시: `pip3 install python-docx`
- `sources:` 프론트매터에 원본 `.docx` 경로를 기록한다: `sources: [raw/파일명.docx]`

### .wikicurate 설정 파일

위키 루트에 위치하는 JSON 설정 파일. 모든 키는 선택적이다.

| 키 | 타입 | 설명 |
|----|------|------|
| `google_profile` | string | Google OAuth 프로필 이름. GSHEET/GDOC/GSLIDES 처리 시 사용. |
| `inbox_path` | string | inbox 절대경로. 미설정 시 `wiki-inbox/` (위키 루트 기준 상대경로) 사용. |

**예시** (SynapseModule/Docs — inbox가 상위 디렉토리에 위치하는 경우):
```json
{
  "google_profile": "im.ds",
  "inbox_path": "/Users/1004790/im.ds@10xtf.ai - Google Drive/공유 드라이브/SynapseModule/wiki-inbox"
}
```

> `/ingest` 무인자 실행 시 이 파일을 읽어 inbox 경로를 결정한다.
> watcher가 인자로 경로를 전달하는 경우에는 이 설정을 무시하고 전달된 경로를 우선 사용한다.

---

### Google 인증 공통 로직

GSHEET / GDOC / GSLIDES 처리 시 아래 헬퍼를 사용한다. 각 섹션의 1단계 코드는 이 헬퍼를 호출하는 것으로 대체된다.

```python
import json, glob, os, pickle
from google_auth_oauthlib.flow import InstalledAppFlow
from google.auth.transport.requests import Request

def _find_wiki_root(start=None):
    """CWD에서 위로 올라가며 wiki/index.md가 있는 디렉토리를 반환. 없으면 None."""
    current = os.path.abspath(start or os.getcwd())
    while True:
        if os.path.exists(os.path.join(current, "wiki", "index.md")):
            return current
        parent = os.path.dirname(current)
        if parent == current:
            return None
        current = parent

def _get_google_creds():
    """
    위키 루트의 .wikicurate에서 google_profile을 읽어 OAuth creds를 반환.
    설정 없음 / 파일 없음 / 인증 실패 시 None 반환 → 호출부에서 fallback 처리.
    """
    CONFIG_DIR = os.path.expanduser("~/.config/wikicurate")
    SCOPES = ["https://www.googleapis.com/auth/drive.readonly"]

    wiki_root = _find_wiki_root()
    if not wiki_root:
        return None

    cfg_path = os.path.join(wiki_root, ".wikicurate")
    if not os.path.exists(cfg_path):
        return None
    try:
        profile = json.load(open(cfg_path)).get("google_profile", "")
    except Exception:
        return None
    if not profile:
        return None

    TOKEN_PATH = os.path.join(CONFIG_DIR, f"token_{profile}.pickle")
    cred_files = glob.glob(os.path.join(CONFIG_DIR, f"client_secret_{profile}.json"))
    if not cred_files:
        return None

    try:
        creds = None
        if os.path.exists(TOKEN_PATH):
            with open(TOKEN_PATH, "rb") as f:
                creds = pickle.load(f)
        if not creds or not creds.valid:
            if creds and creds.expired and creds.refresh_token:
                creds.refresh(Request())
            else:
                flow = InstalledAppFlow.from_client_secrets_file(cred_files[0], SCOPES)
                creds = flow.run_local_server(port=0)
            with open(TOKEN_PATH, "wb") as f:
                pickle.dump(creds, f)
        return creds
    except Exception:
        return None
```

- `google-auth-oauthlib` 미설치 시: `pip3 install google-auth-oauthlib`
- 최초 실행 시 브라우저 인증 필요. 이후 `token_<profile>.pickle`이 자동 갱신됨.

---

### GSHEET

`.gsheet` 파일은 Google Drive 스텁 JSON(`{"url": "...", "resource_id": "..."}`)이다. URL에서 Sheet ID를 추출한 뒤 아래 2단계 순서로 처리한다. **`raw/`에 중간 파일을 저장하지 않는다.**

**1단계 — OAuth** (위키 루트에 `.wikicurate` 파일이 존재하는 경우):

```python
import gspread, json, re

stub = json.load(open("raw/파일명.gsheet"))
sheet_id = re.search(r'/spreadsheets/d/([^/]+)', stub["url"]).group(1)

try:
    creds = _get_google_creds()
    if creds is None:
        raise Exception("fallback")

    gc = gspread.authorize(creds)
    sh = gc.open_by_key(sheet_id)
    for ws in sh.worksheets():
        # 첫 5행을 단일 API 호출로 가져와 로컬에서 헤더 탐색
        rows = ws.get_values("A1:Z5")
        headers = []
        header_row = None
        for i, row in enumerate(rows, start=1):
            non_empty = [v for v in row if str(v).strip()]
            if non_empty:
                headers = row
                header_row = i
                break
        if not headers:
            row_count = 0  # 빈 시트 또는 구조 불명확
        else:
            row_count = ws.row_count - header_row
        # → 시트명, headers, row_count를 wiki에 기록
except Exception:
    # 2단계 fallback으로 강등
    pass
```

- gspread 미설치 시: `pip3 install gspread`

**2단계 — 인증 없음 fallback** (`.wikicurate` 없음 / 프로필 미설정 / 인증 실패 시):

데이터 fetch 없이 URL과 파일명만 wiki 페이지에 기록하고, 본문에 아래 안내 블록을 삽입한다:

```markdown
> **인증 미설정**: Google 인증이 구성되지 않아 시트 데이터를 가져오지 못했습니다.
> 위키 루트에 `.wikicurate` 파일을 생성하고 `google_profile`을 설정하세요.
> 원본: https://docs.google.com/spreadsheets/d/...
```
- `sources:` 프론트매터에 원본 `.gsheet` 경로를 기록한다: `sources: [raw/파일명.gsheet]`

### GDOC

`.gdoc` 파일은 Google Drive 스텁 JSON(`{"url": "...", "resource_id": "..."}`)이다. URL에서 Document ID를 추출한 뒤 아래 2단계 순서로 처리한다. **`raw/`에 중간 파일을 저장하지 않는다.**

**추출 대상 (토큰 절약):** 문서 제목 + 헤딩(H1~H3) 구조 + 각 섹션 첫 문단(200자 이내)

**1단계 — OAuth** (위키 루트에 `.wikicurate` 파일이 존재하는 경우):

```python
import json, re
from googleapiclient.discovery import build

stub = json.load(open("raw/파일명.gdoc"))
doc_id = re.search(r'/document/d/([^/]+)', stub["url"]).group(1)

try:
    creds = _get_google_creds()
    if creds is None:
        raise Exception("fallback")

    service = build("docs", "v1", credentials=creds)
    doc = service.documents().get(documentId=doc_id).execute()

    title = doc.get("title", "")
    sections = []
    got_first_para = False

    for element in doc.get("body", {}).get("content", []):
        para = element.get("paragraph")
        if not para:
            continue
        style = para.get("paragraphStyle", {}).get("namedStyleType", "")
        text = "".join(
            e.get("textRun", {}).get("content", "")
            for e in para.get("elements", [])
            if "textRun" in e
        ).strip()
        if not text:
            continue
        if style in ("HEADING_1", "HEADING_2", "HEADING_3"):
            sections.append({"heading": text, "level": style, "first_para": None})
            got_first_para = False
        elif style == "NORMAL_TEXT" and not got_first_para and sections:
            sections[-1]["first_para"] = text[:200]
            got_first_para = True
    # → title, sections(heading + first_para)를 wiki에 기록
except Exception:
    # 2단계 fallback으로 강등
    pass
```

- google-api-python-client 미설치 시: `pip3 install google-api-python-client`

**2단계 — 인증 없음 fallback** (`.wikicurate` 없음 / 프로필 미설정 / 인증 실패 시):

데이터 fetch 없이 URL과 파일명만 wiki 페이지에 기록하고, 본문에 아래 안내 블록을 삽입한다:

```markdown
> **인증 미설정**: Google 인증이 구성되지 않아 문서 데이터를 가져오지 못했습니다.
> 위키 루트에 `.wikicurate` 파일을 생성하고 `google_profile`을 설정하세요.
> 원본: https://docs.google.com/document/d/...
```

- google-api-python-client 미설치 시: `pip3 install google-api-python-client`
- `sources:` 프론트매터에 원본 `.gdoc` 경로를 기록한다: `sources: [raw/파일명.gdoc]`

### GSLIDES

`.gslides` 파일은 Google Drive 스텁 JSON(`{"url": "...", "resource_id": "..."}`)이다. URL에서 Presentation ID를 추출한 뒤 아래 2단계 순서로 처리한다. **`raw/`에 중간 파일을 저장하지 않는다.**

**추출 대상 (토큰 절약):** 프레젠테이션 제목 + 슬라이드별 제목 + 본문 텍스트(슬라이드당 500자 이내)

**1단계 — OAuth** (위키 루트에 `.wikicurate` 파일이 존재하는 경우):

```python
import json, re
from googleapiclient.discovery import build

SLIDE_BODY_LIMIT = 500  # 슬라이드당 본문 텍스트 최대 글자 수

stub = json.load(open("raw/파일명.gslides"))
pres_id = re.search(r'/presentation/d/([^/]+)', stub["url"]).group(1)

try:
    creds = _get_google_creds()
    if creds is None:
        raise Exception("fallback")

    service = build("slides", "v1", credentials=creds)
    pres = service.presentations().get(presentationId=pres_id).execute()

    title = pres.get("title", "")
    slides = []
    for slide in pres.get("slides", []):
        slide_title = None
        body_parts = []
        for el in slide.get("pageElements", []):
            shape = el.get("shape", {})
            ph_type = shape.get("placeholder", {}).get("type", "")
            text = "".join(
                te.get("textRun", {}).get("content", "")
                for te in shape.get("text", {}).get("textElements", [])
                if "textRun" in te
            ).strip()
            if not text:
                continue
            if ph_type in ("TITLE", "CENTERED_TITLE"):
                slide_title = text
            else:
                body_parts.append(text)
        body = "\n".join(body_parts)[:SLIDE_BODY_LIMIT]
        slides.append({"title": slide_title, "body": body})
    # → title, slides(slide_title + body)를 wiki에 기록
except Exception:
    # 2단계 fallback으로 강등
    pass
```

- google-api-python-client 미설치 시: `pip3 install google-api-python-client`

**2단계 — 인증 없음 fallback** (`.wikicurate` 없음 / 프로필 미설정 / 인증 실패 시):

데이터 fetch 없이 URL과 파일명만 wiki 페이지에 기록하고, 본문에 아래 안내 블록을 삽입한다:

```markdown
> **인증 미설정**: Google 인증이 구성되지 않아 프레젠테이션 데이터를 가져오지 못했습니다.
> 위키 루트에 `.wikicurate` 파일을 생성하고 `google_profile`을 설정하세요.
> 원본: https://docs.google.com/presentation/d/...
```

- google-api-python-client 미설치 시: `pip3 install google-api-python-client`
- `sources:` 프론트매터에 원본 `.gslides` 경로를 기록한다: `sources: [raw/파일명.gslides]`

### DOC

`.doc` 파일(Word 97-2003)은 python-docx로 직접 처리할 수 없다. wiki 페이지에 변환 안내를 기록하고 종료한다.

```markdown
> **변환 필요**: `.doc` 파일은 직접 처리할 수 없습니다.
> 아래 방법으로 `.docx`로 변환 후 다시 ingest하세요.
> LibreOffice: `libreoffice --headless --convert-to docx "raw/파일명.doc" --outdir raw/`
> 또는 Word에서 "다른 이름으로 저장 → .docx"로 변환하세요.
```

- `sources:` 프론트매터에 원본 `.doc` 경로를 기록한다: `sources: [raw/파일명.doc]`

### XLS

`.xls` 파일(Excel 97-2003)은 openpyxl로 직접 처리할 수 없다. wiki 페이지에 변환 안내를 기록하고 종료한다.

```markdown
> **변환 필요**: `.xls` 파일은 직접 처리할 수 없습니다.
> 아래 방법으로 `.xlsx`로 변환 후 다시 ingest하세요.
> LibreOffice: `libreoffice --headless --convert-to xlsx "raw/파일명.xls" --outdir raw/`
> 또는 Excel에서 "다른 이름으로 저장 → .xlsx"로 변환하세요.
```

- `sources:` 프론트매터에 원본 `.xls` 경로를 기록한다: `sources: [raw/파일명.xls]`

### PPT

`.ppt` 파일(PowerPoint 97-2003)은 python-pptx로 직접 처리할 수 없다. wiki 페이지에 변환 안내를 기록하고 종료한다.

```markdown
> **변환 필요**: `.ppt` 파일은 직접 처리할 수 없습니다.
> 아래 방법으로 `.pptx`로 변환 후 다시 ingest하세요.
> LibreOffice: `libreoffice --headless --convert-to pptx "raw/파일명.ppt" --outdir raw/`
> 또는 PowerPoint에서 "다른 이름으로 저장 → .pptx"로 변환하세요.
```

- `sources:` 프론트매터에 원본 `.ppt` 경로를 기록한다: `sources: [raw/파일명.ppt]`

### log.md 기록 규칙

변환 중간 파일이 있더라도 **원본 바이너리 파일명**으로 기록한다.

```
## [날짜] ingest | 파일명.docx
## [날짜] ingest | 파일명.pptx
## [날짜] ingest | 파일명.xlsx
## [날짜] ingest | 파일명.pdf
## [날짜] ingest | 파일명.gsheet
## [날짜] ingest | 파일명.gdoc
## [날짜] ingest | 파일명.gslides
## [날짜] ingest | 파일명.doc
## [날짜] ingest | 파일명.xls
## [날짜] ingest | 파일명.ppt
## [날짜] ingest | 파일명.csv
## [날짜] ingest | 파일명.tsv
```

---

## 핵심 원칙

- `raw/` 파일은 절대 수정하지 않는다.
- 모든 위키 페이지에는 프론트매터를 포함한다.
- **파일명 = `title:` 프론트매터 = `[[링크 텍스트]]`** — 셋이 항상 동일해야 한다. 불일치 시 Obsidian이 0B 파일을 생성한다.
- 소스 하나를 처리할 때 관련 페이지를 한 번에 일괄 갱신한다 (세션을 나누지 않는다).
- 새 정보가 기존 클레임과 충돌하면 해당 페이지에 명시적으로 표기한다.
