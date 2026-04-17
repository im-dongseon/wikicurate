# Design: 스프레드시트 파일 ingest 정책 정의 (XLSX 경량화 + gsheet 신규 지원)

- **Feature ID:** `20260417_spreadsheet_ingest_policy`
- **상태:** Step 2 — Design (승인 대기)

---

## 개정 전/후 비교

### XLSX 섹션 (수정)

**Before:**
```python
import openpyxl
wb = openpyxl.load_workbook("raw/파일명.xlsx")
# 각 시트를 마크다운 테이블로 변환
```
> 전체 행을 마크다운 테이블로 변환 → 데이터 폭발 위험

**After:**
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
        # 빈 시트 또는 5행 안에 헤더 없음 → "빈 시트 또는 구조 불명확"으로 기록
        row_count = 0
    else:
        # ws.max_row는 스타일만 지정된 빈 행을 포함할 수 있으므로 추정치로 기록
        row_count = (ws.max_row or header_row) - header_row
    # → 시트명, headers, row_count(추정치)만 wiki에 기록
```
> 시트명 + 컬럼 헤더 + 행 수만 추출. 실제 데이터 행은 읽지 않는다.  
> 헤더를 5행 안에 찾지 못하면 "빈 시트 또는 구조 불명확"으로 기록한다.  
> **행 수는 추정치**로 표기한다 — openpyxl `max_row`는 서식만 지정된 빈 행을 포함할 수 있다.

---

### gsheet 섹션 (신규 추가)

`.gsheet` 파일은 Google Drive 스텁 JSON(`{"url": "...", "resource_id": "..."}`)이다.  
Sheet ID를 추출한 뒤 아래 3단계 순서로 처리한다.

**1단계 — 서비스 계정 (전체 메타데이터)**

`~/.config/gspread/service_account.json` 존재 시:

```python
import gspread, json, os, re

stub = json.load(open("raw/파일명.gsheet"))
sheet_id = re.search(r'/spreadsheets/d/([^/]+)', stub["url"]).group(1)

gc = gspread.service_account()  # ~/.config/gspread/service_account.json 자동 로드
sh = gc.open_by_key(sheet_id)
for ws in sh.worksheets():
    # 첫 5행을 한 번의 API 호출로 가져와 로컬에서 헤더 탐색
    rows = ws.get_values("A1:Z5")  # 단일 API 호출
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
```

- gspread 미설치 시: `pip3 install gspread`

**2단계 — API 키 fallback (공개 시트 전용)**

`~/.config/gspread/service_account.json` 없고 `GOOGLE_API_KEY` 환경변수 존재 시:

```python
import gspread, os

gc = gspread.api_key(os.environ["GOOGLE_API_KEY"])
sh = gc.open_by_key(sheet_id)
# 이후 동일 (get_values("A1:Z5") → 헤더 탐색 → 행수 기록)
```

> 비공개 시트는 `gspread.exceptions.APIError (403)` 발생 → 3단계로 강등

**3단계 — 인증 없음 fallback (URL 기록)**

서비스 계정도 없고 API 키도 없거나, 2단계에서 403 발생 시:

- 데이터 fetch 없이 URL과 파일명만 wiki 페이지에 기록
- wiki 페이지 본문에 아래 안내 블록 삽입:

```markdown
> **인증 미설정**: Google 인증이 구성되지 않아 시트 데이터를 가져오지 못했습니다.
> 상세 내용을 수집하려면 `~/.config/gspread/service_account.json`을 설정하거나
> `GOOGLE_API_KEY` 환경변수를 지정하세요.
> 원본: https://docs.google.com/spreadsheets/d/...
```

---

## 대상 파일 및 변경 성격

| 파일 | 변경 성격 |
|------|----------|
| `_system/CLAUDE.md` — XLSX 섹션 | 수정 (전체 행 → 헤더+행수 추정치) |
| `_system/CLAUDE.md` — gsheet 섹션 | 신규 추가 |
| `_system/CLAUDE.md` — log.md 기록 규칙 | 수정 (gsheet 원본 파일명 예시 추가) |
| `_system/wiki-schema.md` | 동일 변경 적용 (`CLAUDE.md`와 미러 관계) |
| `_system/commands/setup.md` | 수정 (gspread 의존성 설치 확인 단계 추가) |

---

## 연계 룰/스킬 정합성 검토

- `_system/commands/ingest.md`: "파일 내용을 읽는다" 단계에서 형식별 처리를 CLAUDE.md에 위임하므로 ingest.md 수정 불필요.
- PDF·PPTX 정책과 구조 동일 (`raw/`에 중간 파일 저장 안 함, sources 프론트매터에 원본 경로 기록).
- gsheet는 PPTX/XLSX와 달리 중간 `.md` 파일을 생성하지 않고 wiki 페이지를 직접 작성한다.
- `_system/CLAUDE.md`와 `_system/wiki-schema.md`는 동일 내용의 미러 파일이므로 항상 함께 수정한다.

---

## 미결 사항 (Unresolved Issues)

없음
