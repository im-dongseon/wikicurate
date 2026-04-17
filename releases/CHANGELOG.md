# CHANGELOG

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
