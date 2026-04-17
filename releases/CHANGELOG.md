# CHANGELOG

## [0.2.4] - 2026-04-17

### Added
- **Codex CLI 지원:** `WIKICURATE_AGENT=codex` 설정 시 Codex CLI를 통한 자동 ingest/lint 실행 (Playbook 방식)
- **에이전트 우선순위 조정:** `codex` → `claude` → `gemini` 순으로 사용 가능한 에이전트 자동 탐색 및 fallback
- **에이전트별 프롬프트 최적화:** Codex의 경우 `/command` 대신 `_system/commands/`의 파일을 읽고 실행하도록 최적화된 프롬프트 전달
- **watcher 상태 확인 개선:** `watcher.sh status` 실행 시 실제 동작 중인 PID 표시 및 등록 상태(중지/실행) 세분화

### Fixed
- **격리 재시도 루프 해결:** `isolate` 실패(예: 권한 문제로 `mv` 실패) 시 DB에서 해당 파일을 즉시 제거하여 무한 재시도 현상 방지

### Changed
- **범용 에이전트 가이드:** `_system/wiki-schema.md`를 특정 에이전트(Claude)에 종속되지 않는 `WikiCurate Agent Guide`로 개정

---

## [0.2.3] - 2026-04-17

### Added
- **GSHEET ingest 지원:** `.gsheet` 파일(Google Drive 스텁) ingest 정책 신규 도입
  - 3단계 fallback: 서비스 계정 → API 키 → URL 기록(인증 없음)
  - `gspread.get_values("A1:Z5")` 단일 API 호출로 헤더 탐색 (할당량 최소화)
- **XLSX ingest 경량화:** 전체 행 마크다운 테이블 → 시트명 + 컬럼 헤더 + 행 수(추정치)만 추출
  - 빈 1행 대응: 최대 5행 탐색으로 첫 번째 비어있지 않은 행을 헤더로 채택
  - `read_only=True, data_only=True` 적용으로 메모리 절약
- **Python 의존성 통합 관리:** `setup.md`에 openpyxl·python-pptx·gspread 설치 확인 단계 추가

### Changed
- XLSX: `raw/<이름>.md` 중간 파일 생성 방식 → wiki 페이지 직접 작성으로 변경

---

## [0.2.2] - 2026-04-17

### Added
- **ingest 자동 재시도:** ingest 실패 파일을 SQLite DB(`_state/data/wikicurate-retries.db`)에 기록하여 다음 주기에 자동 재시도
- **최대 5회 재시도:** 5회 재시도 모두 실패 시 `raw/error/`로 자동 격리 (확장자 보존, 타임스탬프 접미사)
- **유령 레코드 청소:** 사용자가 `raw/`에서 파일을 수동 삭제한 경우 DB에서 해당 레코드 자동 제거
- **재시도 로그:** `[RETRY N/5]`, `[FAIL]`, `[ISOLATED]` 접두사로 재시도 상태를 watcher.log에 기록
- **`_state/` 디렉토리:** 볼트 루트에 런타임 상태 전용 폴더 도입 (`_system/`과 동일한 `_` 컨벤션, rsync 제외)
- **sqlite3 의존성 검사:** `watcher.sh register` 및 `watch-ingest.sh` 시작 시 sqlite3 설치 여부 확인 및 PATH 주입

### Changed
- `watch-ingest.sh` 처리 루프: 큐가 비어 있어도 DB에 재시도 대기 파일이 있으면 처리 주기 실행

---

## [0.2.1] - 2026-04-17

### Added
- **자동 lint:** ingest 배치 성공 후 자동으로 `/lint` 실행 — 고아 페이지·끊긴 링크·모순 클레임 즉시 감지·수정
- **ingest 실패 원인 로그:** 실패한 파일의 에이전트 출력을 watcher.log에 기록
- **lint 결과 로그:** lint 성공/실패 여부 및 실행 결과를 watcher.log에 기록
- **로그 확인 명령:** `watcher.sh log` 서브커맨드 추가 (실시간 스트리밍)
- **VERSION 파일:** `_system/VERSION`을 단일 버전 소스로 도입 — 배포 시 각 볼트의 `_system/VERSION`으로 자동 복사되어 배포 버전 확인 가능

---

## [0.2.0] - 2026-04-17

### Added
- **자동 ingest:** `fswatch` 기반 `raw/` 디렉토리 감시 및 10분 주기 자동 ingest 실행 (`scripts/watch-ingest.sh`)
- **watcher 관리:** macOS launchd Launch Agent 등록/해제/상태 확인 (`scripts/watcher.sh register|unregister|status`)
- **배포 통합:** `deploy.sh` 실행 시 ingest-watcher 자동 등록 (로그인 시 자동 시작, 크래시 시 자동 재시작)
- **멀티 KMS 지원:** `.env`의 `DEPLOY_PATHS` 전체를 감시 대상으로 사용 — 여러 볼트 동시 감시
- **에이전트 fallback:** `WIKICURATE_AGENT` 환경변수로 에이전트 선택, 미설치 시 Claude → Gemini 순 자동 전환

---

## [0.1.0] - 2026-04-16

### Added
- **아키텍처:** raw/, wiki/, _system/ 3레이어 구조와 명령 기반 운영 체계 반영
- **배포 스크립트:** 다중 경로 배포 및 드라이런을 지원하는 deploy.sh 생성
