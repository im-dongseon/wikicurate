# Review: fswatch 기반 자동 ingest

- **Feature ID:** `20260417_fswatch_auto_ingest`
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

### design.md 변경 항목 반영 여부

| 파일 | 설계 | 구현 | 비고 |
|------|------|------|------|
| `scripts/watch-ingest.sh` | 신규 추가 | ✓ 생성 | 실행 권한 부여 완료 |
| `scripts/watcher.sh` | 신규 추가 | ✓ 생성 | 실행 권한 부여 완료 |
| `deploy.sh` | `watcher.sh register` 호출 추가 | ✓ 수정 | dry-run 분기 외부에 정확히 위치 |

### 설계 대비 구현 차이

| 항목 | 설계 | 구현 | 판단 |
|------|------|------|------|
| `.env` 로드 순서 | AGENT/INTERVAL 선언 후 source | source 후 AGENT/INTERVAL 선언 | **개선** — `.env`에서 오버라이드 가능하도록 순서 수정 |
| watched=0 검증 | 미포함 | 감시 대상 0개면 오류 종료 추가 | **개선** — 빈 상태로 루프 진입 방지 |
| `mkdir -p LaunchAgents` | 미포함 | `watcher.sh register`에 추가 | **개선** — 신규 사용자 환경 대비 |

### `_system/` 충돌 여부

`_system/` 내 파일 변경 없음. 충돌 없음.

### 참조 파일 존재 여부

| 참조 | 존재 여부 |
|------|-----------|
| `$SCRIPT_DIR/.env` | ✓ 존재 (`DEPLOY_PATHS` 포함) |
| `$SCRIPT_DIR/scripts/watch-ingest.sh` | ✓ 존재 (watcher.sh가 참조) |
| `$HOME/Library/LaunchAgents/` | ✓ macOS 표준 경로 (mkdir -p로 보장) |

### `wiki/index.md` 갱신 필요 여부

`scripts/`는 Dev Zone 산출물로 KMS 운영과 무관. 갱신 불필요.

### 연계 정합성

| 연계 | 결과 |
|------|------|
| `deploy.sh` → `watcher.sh register` 호출 | ✓ dry-run이 아닐 때만 실행 |
| `watch-ingest.sh` → `.env` DEPLOY_PATHS 사용 | ✓ `deploy.sh`와 동일 패턴 |
| `watcher.sh` → `watch-ingest.sh` 절대경로 참조 | ✓ SCRIPT_DIR 기반 |
| `/ingest $file` 인자 전달 | ✓ `ingest.md` $ARGUMENTS 방식과 호환 |

---

## 변경 이력

| 버전 | 일자 | 주요 변경 |
|------|------|----------|
| v1 | 2026-04-17 | 초안 리뷰 — 모든 DoD 항목 충족 확인 |
| v2 | 2026-04-17 | Step 5 배포 중 버그 발견 → Step 3 복귀 후 수정: `set -u` 환경에서 빈 배열 `seen[*]` unbound variable 오류, `[[ ${#seen[@]} -gt 0 ]]` 선행 검사로 해결 |
