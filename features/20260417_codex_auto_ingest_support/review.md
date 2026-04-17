# Review: Codex 자동 ingest 지원

- **Feature ID:** `20260417_codex_auto_ingest_support`
- **작업 시작일:** 2026-04-17
- **상태:** Step 4 — Review

---

## DoD 체크리스트

| 검증 항목 | 충족 여부 |
|-----------|-----------|
| design.md의 모든 변경 항목이 implementation에 반영됨 | [x] |
| `_system/` 내 기존 파일과 충돌(중복 정의)이 없음 | [x] |
| 새 명령이 참조하는 다른 파일이 실제로 존재함 | [x] |
| `wiki/index.md` 등 내비게이션 갱신 필요 여부 확인 | [x] |
| 미반영 항목이 있다면 사유와 후속 Feature ID가 명시됨 | [x] |
| 연계 룰/스킬과의 정합성이 확인됨 | [x] |

---

## 항목별 검증

| 파일 | 설계 반영 결과 |
|------|----------------|
| `scripts/watch-ingest.sh` | `codex` 기본값, 실행기 선택, playbook 프롬프트 분기 반영 |
| `scripts/watcher.sh` | launchd PATH 수집 대상에 `codex` 추가 |
| `_system/wiki-schema.md` | 에이전트 중립 표현 및 비-slash 실행 규칙 정리 |
| `README.md` | Codex 기본값/예시 반영 |
| `README.en.md` | Codex 기본값/예시 반영 |

### 참조 파일 존재 여부

| 참조 | 결과 |
|------|------|
| `_system/commands/ingest.md` | ✓ 존재 |
| `_system/commands/lint.md` | ✓ 존재 |
| `scripts/watch-ingest.sh` | ✓ 존재 |
| `scripts/watcher.sh` | ✓ 존재 |

### `wiki/index.md` 갱신 필요 여부

Dev Zone 문서/스크립트 변경만 포함하므로 갱신 불필요.

### 미반영 항목

없음

### 연계 정합성

- `watch-ingest.sh`는 기존 retry/lint 흐름을 유지하면서 Codex 실행기만 추가 지원한다.
- `watcher.sh`는 launchd PATH 보강만 수행하므로 기존 등록/해제 동작과 충돌하지 않는다.
- `_system/commands/*.md` playbook 기반 실행 방식은 Codex의 non-slash 환경과 정합적이다.

---

## 변경 이력

| 버전 | 일자 | 주요 변경 |
|------|------|----------|
| v1 | 2026-04-17 | Codex 자동 ingest 지원 초안 리뷰 |
| v2 | 2026-04-17 | Step 5 운영 검증 중 버그 발견 후 Step 3 복귀: Codex 옵션 순서 수정, playbook 프롬프트의 shell command substitution 제거, 격리/에러 저장 로직 보강 |
| v3 | 2026-04-17 | Step 5 재검증 중 버그 발견 후 Step 3 복귀: sqlite3 busy_timeout 출력이 retry_count 조회값에 섞이는 문제를 `-cmd` 사용으로 수정 |
| v4 | 2026-04-17 | Step 5 재검증 중 버그 발견 후 Step 3 복귀: `PRAGMA busy_timeout`도 출력값을 남겨 재시도 카운트를 오염시키므로 `.timeout`으로 재수정 |
