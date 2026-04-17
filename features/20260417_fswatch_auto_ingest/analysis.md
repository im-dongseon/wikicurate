# Analysis: fswatch 기반 자동 ingest

- **Feature ID:** `20260417_fswatch_auto_ingest`
- **작업 시작일:** 2026-04-17
- **상태:** Step 1 — Analysis (완료)

---

## 배경 및 목적

현재 `/ingest` 커맨드는 사용자가 수동으로 실행해야만 동작한다.
`raw/` 디렉토리에 파일을 추가하거나 수정한 뒤 매번 직접 커맨드를 입력하는 것은 마찰이 크다.

`fswatch`를 이용해 `raw/` 디렉토리의 변경을 10분 주기로 감지하고,
Claude 또는 Gemini 에이전트를 통해 자동 ingest를 실행하여 이 마찰을 제거한다.

---

## 현행 진단

| 항목 | 현황 | 비고 |
|------|------|------|
| 자동 ingest 스크립트 | **없음** | 수동 실행만 가능 |
| fswatch 설치 | **미설치** | `brew install fswatch` 필요 |
| `raw/` 디렉토리 | 미생성 | KMS 운영 시작 시 생성 |
| Claude CLI 권한 플래그 | **확인 완료** | `--dangerously-skip-permissions` |
| Gemini CLI 권한 플래그 | **확인 완료** | `--yolo` |

### 해결해야 할 결함

1. **수동 실행 의존성**: 파일을 추가한 뒤 ingest를 잊거나 지연하는 경우 wiki가 stale 상태로 남음
2. **권한 프롬프트 블로킹**: 에이전트 실행 시 도구 승인 요청이 발생하면 자동화 흐름이 깨짐
3. **실행 블로킹**: ingest가 동기 실행되면 감시 프로세스 전체가 대기 상태가 됨

---

## 에이전트 CLI 비교 (검토 결과)

대상 에이전트: **Claude, Gemini** (설치 확인 완료)

| 에이전트 | 설치 경로 | 비대화형 플래그 | 권한 우회 플래그 | 자동화 호출 형태 |
|----------|-----------|-----------------|-----------------|-----------------|
| Claude | `/usr/local/bin/claude` | `-p` / `--print` | `--dangerously-skip-permissions` | `claude --dangerously-skip-permissions -p "/ingest <file>"` |
| Gemini | `/opt/homebrew/bin/gemini` | `-p` / `--prompt` | `-y` / `--yolo` | `gemini --yolo -p "/ingest <file>"` |

**에이전트 선택 전략:** 스크립트 기동 시 환경변수 `WIKICURATE_AGENT`(기본값: `claude`)로 지정.
미설치 에이전트 지정 시 fallback으로 나머지 에이전트 시도.

---

## 유스케이스

| # | 이벤트 | 기대 동작 |
|---|--------|-----------|
| UC-1 | `raw/`에 신규 파일 생성 | 10분 이내 자동 ingest 실행 |
| UC-2 | `raw/`의 기존 파일 내용 수정 | 10분 이내 자동 ingest 실행 |
| UC-3 | ingest 실행 중 추가 변경 발생 | 현재 실행 완료 후 다음 주기에 처리 (중복 실행 방지) |
| UC-4 | 스크립트 실행 중 권한 요청 발생 | 권한 우회 플래그로 프롬프트 없이 자동 통과 |
| UC-5 | 지정 에이전트 미설치 | fallback 에이전트로 자동 전환 |

---

## 개정 범위

| 대상 | 변경 성격 | 비고 |
|------|-----------|------|
| `scripts/watch-ingest.sh` | **신규 추가** | 감시 + 배치 트리거 스크립트 |
| `_system/` 내 파일 | **변경 없음** | `/ingest` 커맨드 로직은 그대로 활용 |
| `CLAUDE.md` / `AGENTS.md` | **변경 없음** | 자동화 스크립트는 Dev Zone(루트) 산출물 |

### 기술 방향 (설계 단계 이전 요약)

- **감지 방식:** fswatch로 `raw/` 감시 → 변경된 파일 경로를 큐 파일(`/tmp/wikicurate-queue`)에 누적
- **실행 주기:** 10분 단위 루프(`sleep 600`)로 큐를 읽어 ingest 일괄 트리거
- **비동기 실행:** `... &` 백그라운드 실행으로 감시 루프와 ingest 실행 완전 분리
- **중복 방지:** lock 파일(`/tmp/wikicurate-ingest.lock`)로 동시 실행 차단; 큐는 실행 직전 drain
- **권한 우회:** 에이전트별 플래그(`--dangerously-skip-permissions` / `--yolo`) 적용

---

## 이 Feature의 성공 기준 (Definition of Done)

- [ ] `raw/`에 파일을 추가하면 10분 이내에 자동으로 ingest가 실행된다
- [ ] `raw/`의 기존 파일을 수정하면 10분 이내에 자동으로 ingest가 실행된다
- [ ] ingest 실행 도중 추가 변경이 와도 현재 실행이 완료된 후 다음 주기에 처리된다
- [ ] Claude 또는 Gemini 중 어느 에이전트로도 실행 가능하다 (`WIKICURATE_AGENT` 환경변수로 선택)
- [ ] 권한 프롬프트로 인한 블로킹이 없다
- [ ] 감시 프로세스와 ingest 실행 프로세스가 독립적으로 동작한다 (비동기)
