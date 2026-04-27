# Analysis: Linux 호환성 지원

- **Feature ID**: 20260424_linux_compat
- **작성일**: 2026-04-24

---

## 배경 및 목적

WikiCurate를 사내 리눅스 서버에 배포하기 위해 현재 macOS 전용으로 구현된 스크립트를 Linux(Ubuntu/Debian 계열)에서도 동작하도록 수정합니다.

---

## 현행 진단

### [W-01] watcher.sh — launchd/plist 의존성 (심각)

| 항목 | 내용 |
|------|------|
| 파일 | `scripts/watcher.sh` |
| 문제 | 데몬 등록·해제·상태 확인이 전부 `launchctl` / LaunchAgent plist 기반 |
| 영향 | Linux에서 `register`, `unregister`, `status` 명령 전체 동작 불가 |
| 근거 | `~/Library/LaunchAgents` 경로 하드코딩, `launchctl load/unload/list` 직접 호출 |

### [W-02] watch-ingest.sh — fswatch 의존성 (심각)

| 항목 | 내용 |
|------|------|
| 파일 | `scripts/watch-ingest.sh` |
| 문제 | 파일 감시에 `fswatch` 사용 (macOS Homebrew 패키지) |
| 영향 | Linux에서 ingest-watcher 기능 전체 마비 |
| 근거 | `fswatch` 미설치 시 에러 종료, `brew install fswatch` 안내 메시지 |

### [W-03] watch-ingest.sh — md5 명령어 차이 (경미)

| 항목 | 내용 |
|------|------|
| 파일 | `scripts/watch-ingest.sh` |
| 문제 | BSD `md5` 명령어 사용 (Linux는 `md5sum`) |
| 영향 | 임시 파일명 생성 실패 |
| 근거 | `echo "$root" \| md5 \| cut -c1-8` 패턴 다수 사용 |

### [W-04] 전체 스크립트 — brew 설치 안내 (경미)

| 항목 | 내용 |
|------|------|
| 파일 | `deploy.sh`, `scripts/watch-ingest.sh`, `scripts/daily-rescan.sh` |
| 문제 | 의존성 미설치 시 `brew install` 안내 |
| 영향 | Linux 사용자 혼란 |

---

## 개정 범위 결정

**접근 방식**: 단일 파일 내 OS 분기 (`uname -s` 감지)

| 파일 | 변경 성격 | 주요 변경 내용 |
|------|-----------|---------------|
| `scripts/watcher.sh` | 수정 | OS 감지 추가, Linux용 systemd unit 파일 생성·등록 로직 추가 |
| `scripts/watch-ingest.sh` | 수정 | `fswatch` → `inotifywait` 분기, `md5` → `md5sum` 분기 |
| `scripts/daily-rescan.sh` | 수정 | brew 안내 메시지 OS 조건부 처리 |
| `deploy.sh` | 수정 | brew 안내 메시지 OS 조건부 처리 |

**변경하지 않는 것**: `_system/`, `wikicurate.yaml`, Python 인라인 스크립트 (크로스플랫폼 호환)

---

## Definition of Done

- [ ] macOS에서 기존 동작이 그대로 유지됨 (회귀 없음)
- [ ] Ubuntu 22.04 환경에서 `watcher.sh register/unregister/status` 정상 동작
- [ ] Ubuntu 22.04 환경에서 `wiki-inbox/`에 파일 투입 시 자동 ingest 트리거 동작
- [ ] `deploy.sh` 실행 시 OS에 맞는 안내 메시지 출력
- [ ] systemd user service로 서버 재부팅 후에도 watcher 자동 복구
