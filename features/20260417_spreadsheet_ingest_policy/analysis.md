# Analysis: 스프레드시트 파일 ingest 정책 정의 (XLSX 경량화 + gsheet 신규 지원)

- **Feature ID:** `20260417_spreadsheet_ingest_policy`
- **작업 시작일:** 2026-04-17
- **상태:** Step 1 — Analysis (Completed)

---

## 배경 및 목적

현재 `_system/CLAUDE.md`에는 XLSX를 "전체 행을 마크다운 테이블로 변환"하는 방식으로 정의하고 있으며, `.gsheet` 형식에 대한 처리 정책은 전혀 없다. 두 형식 모두 데이터가 방대할 수 있어 wiki 페이지 품질과 처리 안정성을 해칠 수 있다.

## 현행 진단 (결함 목록)

| # | 결함 | 근거 |
|---|------|------|
| 1 | XLSX 전체 행 추출 — wiki 페이지 수천 줄 가능 | `_system/CLAUDE.md` XLSX 섹션: "각 시트를 마크다운 테이블로 변환" |
| 2 | `.gsheet` 처리 정책 부재 — URL 스텁 JSON만 읽혀 의미 없는 페이지 생성 | `_system/CLAUDE.md`에 gsheet 섹션 없음 |
| 3 | gsheet 인증 미설정 시 fallback 없음 — Google API 호출 실패 시 처리 중단 | 미정의 |

## 개정 범위 결정

- **대상 파일:** `_system/CLAUDE.md` — 바이너리·비텍스트 소스 처리 섹션
- **변경 성격:**
  - XLSX 섹션: 수정 (전체 행 → 헤더 + 행수)
  - gsheet 섹션: 신규 추가 (gspread 기반, 계층적 fallback)

## 이 Feature의 성공 기준 (Definition of Done)

- [x] XLSX 정책이 "시트명 + 컬럼 헤더 + 행 수"만 추출하도록 변경됨
- [x] gsheet 섹션이 신규 추가되고 아래 3단계 fallback이 명시됨
  - 1단계: 서비스 계정 (`~/.config/gspread/service_account.json`)
  - 2단계: API 키 (`GOOGLE_API_KEY` 환경변수, 공개 시트 전용)
  - 3단계: URL + 파일명만 기록 + 인증 안내 삽입
- [x] log.md 기록 규칙에 gsheet 원본 파일명 기록 방식이 추가됨
- [x] 기존 PDF·PPTX 정책과 충돌 없음
