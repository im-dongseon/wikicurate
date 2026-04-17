# Review: 스프레드시트 파일 ingest 정책 정의 (XLSX 경량화 + gsheet 신규 지원)

- **Feature ID:** `20260417_spreadsheet_ingest_policy`
- **상태:** Step 4 — Review (Completed)

---

## DoD 체크리스트

| 검증 항목 | 충족 여부 |
|-----------|-----------|
| design.md의 모든 변경 항목이 implementation에 반영됨 | ✅ |
| `_system/` 내 기존 파일과 충돌(중복 정의)이 없음 | ✅ |
| 새 명령이 참조하는 다른 파일이 실제로 존재함 | ✅ |
| `wiki/index.md` 등 내비게이션 갱신 필요 여부 확인 | ✅ (불필요 — 정책 문서만 변경) |
| 미반영 항목이 있다면 사유와 후속 Feature ID가 명시됨 | ✅ (미반영 없음) |
| 연계 룰/스킬과의 정합성이 확인됨 | ✅ |

---

## 반영 내역 확인

### `_system/CLAUDE.md` (= `_system/wiki-schema.md` 심볼릭 링크)

| 항목 | 반영 여부 |
|------|----------|
| XLSX: 전체 행 → 헤더+행수(추정치) 추출로 변경 | ✅ |
| XLSX: `read_only=True, data_only=True` 적용 | ✅ |
| XLSX: 최대 5행 탐색으로 헤더 탐지 (빈 1행 대응) | ✅ |
| XLSX: `ws.max_row` 추정치 주의사항 명시 | ✅ |
| GSHEET: 신규 섹션 추가 | ✅ |
| GSHEET: 3단계 fallback (서비스계정 → API키 → URL) | ✅ |
| GSHEET: `get_values("A1:Z5")` 단일 API 호출로 최적화 | ✅ |
| GSHEET: 빈 시트 대응 (5행 탐색 + row_count=0) | ✅ |
| log.md 기록 규칙: `.gsheet` 예시 추가 | ✅ |

### `_system/commands/setup.md`

| 항목 | 반영 여부 |
|------|----------|
| gspread 의존성 설치 확인 단계 추가 | ✅ |
| openpyxl, python-pptx 의존성도 함께 통합 정리 | ✅ |
| gspread 인증 설정 안내 (선택, fallback 동작 명시) | ✅ |

---

## 변경 이력

| 버전 | 일자 | 주요 변경 |
|------|------|----------|
| v1 | 2026-04-17 | 초안 구현 및 리뷰 완료 |
