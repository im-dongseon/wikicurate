# Feature 배포 이력

<!-- append-only — 최신 항목이 파일 끝에 위치 -->

---

## [2026-04-17] fswatch_auto_ingest

- **목적**: `raw/` 파일 변경을 감지하여 10분 주기로 `/ingest`를 자동 실행. 수동 실행 의존성 제거
- **로직**: fswatch로 변경 경로를 루트별 queue 파일에 누적 → 타이머 루프에서 일괄 처리. ingest는 백그라운드 서브셸로 실행해 감시 루프와 완전 분리. lock 파일로 동시 실행 방지
- **결정 이유**: launchd PATH 제한 문제를 등록 시점에 실제 바이너리 경로를 수집해 plist에 주입하는 방식으로 해결. `set -u` 환경에서 빈 배열 unbound variable 오류는 `[[ ${#seen[@]} -gt 0 ]]` 선행 검사로 해결
- **트레이드오프**: 없음
- **결론**: v0.2.0 배포. `scripts/watch-ingest.sh`, `scripts/watcher.sh`, `deploy.sh` 도입
---

## [2026-04-17] auto_lint_after_ingest

- **목적**: ingest 배치 완료 후 `/lint`를 자동 실행해 고아 페이지·끊긴 링크·모순 클레임을 즉시 감지·수정
- **로직**: ingest 성공 건수 > 0일 때만 lint 실행. 기존 ingest 서브셸 내부에서 실행해 동일 lock 공유
- **결정 이유**: 전부 실패 시 wiki 변경 없으므로 lint 불필요. lock 공유로 경쟁 조건 없음
- **트레이드오프**: lint 중 다음 주기 도래 시 연기 처리 (의도된 동작)
- **결론**: v0.2.1 배포. `_system/VERSION` 도입으로 단일 버전 소스 확보
---

## [2026-04-17] ingest_retry_logic

- **목적**: ingest 실패 파일을 SQLite DB에 기록해 다음 주기 자동 재시도(최대 5회). 5회 실패 시 `raw/error/`로 격리
- **로직**: DB 위치 `$root/_state/data/wikicurate-retries.db`. WAL 모드 + Busy Timeout + UPSERT로 다중 서브셸 동시 쓰기 정합성 보장. 격리 시 확장자 보존: `note.md` → `note.YYYYMMDD_HHMMSS.md`
- **결정 이유**: `/tmp` 대신 persist 경로에 DB 배치해 재부팅 후에도 재시도 상태 보존. DB 조회를 메인 루프에서 수행해 중복 배분 방지
- **트레이드오프**: SQLite 의존성 추가
- **결론**: v0.2.2 배포
---

## [2026-04-17] spreadsheet_ingest_policy

- **목적**: XLSX 전체 행 추출 방식을 경량화하고, `.gsheet`(Google Drive 스텁) ingest 정책 신규 도입
- **로직**: XLSX → 시트명 + 컬럼 헤더 + 행 수(추정치)만 추출. GSHEET → 서비스 계정 → API 키 → URL 기록 3단계 fallback. `get_values("A1:Z5")` 단일 API 호출로 Google API 할당량 최소화
- **결정 이유**: 전체 행 추출은 토큰 낭비. `raw/` 중간 파일 없이 wiki 직접 작성으로 XLSX 정책 일관성 확보
- **트레이드오프**: 없음
- **결론**: v0.2.3 배포
---

## [2026-04-17] codex_auto_ingest_support

- **목적**: 자동 ingest watcher의 기본 에이전트를 `codex`로 변경하고 Codex 비대화형 실행 흐름 지원
- **로직**: `build_agent_prompt()` 헬퍼로 에이전트별 playbook 기반 자연어 프롬프트 분기. 에이전트 우선순위: codex → claude → gemini. `wiki-schema.md`를 에이전트 중립 표현(WikiCurate Agent Guide)으로 개정
- **결정 이유**: Codex는 slash command를 네이티브로 실행하지 않으므로 플레이북 직접 참조 방식 필요
- **트레이드오프**: sqlite3 `.timeout` 방식 채택으로 busy_timeout 출력 오염 방지 (v3→v4 수정)
- **결론**: v0.2.4 배포
---

## [2026-04-20] google_oauth_profile

- **목적**: gcloud ADC 제거 환경 대응. 위키별로 다른 Google 계정을 쓸 수 있도록 OAuth 프로필 기반 인증 도입. GDOC/GSLIDES ingest 신규 도입, DOCX ingest 신규 도입
- **로직**: 위키 루트 `.wikicurate`의 `google_profile` → `~/.config/wikicurate/client_secret_{profile}.json` + `token_{profile}.pickle` 선택. `_get_google_creds()` 실패 시 None 반환 → 호출부 fallback. SA 방식 시도 후 OAuth로 최종 결정
- **결정 이유**: SA(서비스 계정)는 공유 드라이브 접근 제한으로 실사용 불가 확인 → 개인 OAuth 방식 채택. GSHEET/GDOC/GSLIDES 동일 헬퍼 공유로 인증 로직 중복 제거
- **트레이드오프**: 최초 실행 시 브라우저 인증 필요. token pickle 파일 관리 필요
- **결론**: v0.2.5 배포. DOC/XLS/PPT fallback(변환 안내) 동시 도입
---

## [2026-04-22] csv_tsv_ingest

- **목적**: CSV/TSV 파일 ingest 정책 부재로 에이전트마다 다른 결과를 내는 문제 해소
- **로직**: 파이썬 내장 `csv` 모듈로 구분자 자동 감지(Sniffer). 헤더 + 행 수만 추출해 wiki 직접 작성. UTF-8(BOM 대응) → cp949 인코딩 fallback
- **결정 이유**: XLSX 정책과 동일하게 요약 추출. 토큰 절약 + 중간 파일 없음
- **트레이드오프**: 없음
- **결론**: `_system/wiki-schema.md`에 CSV/TSV 섹션 추가 및 log.md 규칙 보완
---

## [2026-04-22] inbox_flow_redesign

- **목적**: `raw/` 직접 투입 시 fswatch 탐지 불안정 문제 해소. `wiki-inbox/`(드롭존)와 `raw/`(아카이브) 역할 분리
- **로직**: `wiki-inbox/` → `raw/` 이동 후 wiki 작성. 이동 실패 시 skip, wiki 작성 실패 시 `raw/`에 잔류 → 다음 주기 자동 재처리. SQLite는 retry_count 전용으로 축소. 설정 포맷 `.env` → `wikicurate.yaml` 전환. `deploy.sh` 인터랙티브 마법사 도입
- **결정 이유**: 폴더 상태 머신으로 미처리/완료/격리를 직관적으로 표현. Google Drive 마운트 경로에서 이벤트 누락 방지를 위해 감시 대상을 `wiki-inbox/`로 변경
- **트레이드오프**: yq 의존성 추가. 기존 `.env` 사용자는 마이그레이션 필요
- **결론**: v0.2.6 기반 배포
---

## [2026-04-22] ingest_inbox_cfg

- **목적**: `/ingest` 무인자 실행 시 외부 inbox 경로를 인식하지 못하는 문제 패치 (inbox_flow_redesign 후속)
- **로직**: `ingest.md` 무인자 실행 시 위키 루트 `.wikicurate`의 `inbox_path` 키 우선 참조 → 없으면 `wiki-inbox/` 상대경로 fallback. `_system/wiki-schema.md`에 `.wikicurate` 설정 예시 추가
- **결정 이유**: watcher는 inbox 절대경로를 인자로 전달하지만 수동 실행 및 fallback 경로에서 경로 불일치 발생. `.wikicurate` 파일을 per-wiki 설정 소스로 확립
- **트레이드오프**: 없음
- **결론**: SynapseModule/Docs처럼 deploy 외부에 inbox가 있는 위키에서 수동 `/ingest` 정상 동작
---

## [2026-04-23] graphify_integration

- **목적**: graphify(knowledge graph CLI)를 4개 에이전트(Claude/Codex/Gemini/Copilot)에 always-on 통합하고, graph 빌드 책임을 에이전트 커맨드에서 `watch-ingest.sh` 인프라로 이동
- **로직**:
  - `ingest.md` / `lint.md`에서 graphify 빌드 스텝 제거
  - `watch-ingest.sh`가 lint 성공 후 `graphify update .`를 직접 실행 (graphify 미설치 시 건너뜀, 실패 시 non-fatal)
  - `graphify.md`를 커스텀 빌더에서 graphifyy CLI 래퍼로 교체
  - `deploy.sh` Step 2: AGENTS.md / GEMINI.md를 symlink → 실파일(wiki-schema 복사 + graphify always-on 섹션)로 전환
  - `deploy.sh` Step 7/8/9: `.codex/hooks.json`, `.gemini/settings.json`, `.github/copilot-instructions.md` 신규 생성
  - `.claude/settings.json`에 PreToolUse 훅 추가 (Glob/Grep 트리거 → GRAPH_REPORT.md 존재 시 컨텍스트 주입)
  - `wiki-schema.md` 지식 그래프 섹션 업데이트 (watch-ingest.sh 빌드 경로, GRAPH_REPORT.md 병기)
- **결정 이유**: graphifyy CLI 단일 경로로 통일해 커스텀 빌더와의 "two-graphify" 충돌 해소. 빌드를 인프라 레이어로 이동해 ingest/lint 커맨드가 순수 wiki 작업에만 집중하도록 분리
- **트레이드오프**: `daily_rescan` 경로의 lint 성공 후 graphify 빌드가 없는 공백 발생 → daily_rescan feature에서 해소. Codex hooks.json / Gemini BeforeTool 훅 포맷은 공식 문서 미검증 (배포 후 확인 필요)
- **결론**: 2개 wiki(wiki-agent, SynapseModule/Docs)에 정상 배포 완료. AGENTS.md/GEMINI.md 실파일 전환, PreToolUse 훅 활성화. graphify 설치 후 다음 ingest+lint 사이클부터 자동 그래프 빌드 시작
---

## [2026-04-23] daily_rescan

- **목적**: Google 스텁 파일(.gdoc/.gsheet/.gslides)은 내용이 바뀌어도 fswatch가 감지하지 못해 wiki가 stale해지는 문제 해소. 매일 07/10/13/16/19/21시(6회/일)에 자동 재ingest + raw/ 미처리 파일 복구
- **로직**:
  - `scripts/daily-rescan.sh` 신규: wikicurate.yaml 읽기 → Pass 1(Google 스텁 개별 ingest) → Pass 2(무인자 ingest, raw/ 미기록 파일 복구) → lint+graphify(ok>0 또는 pass2_ok=true 시)
  - `scripts/watcher.sh` 수정: RESCAN 변수 추가, register/unregister에 daily-rescan launchd job 처리, status에 두 job 표시, rescan-log 서브커맨드 추가, PATH 주입에 graphify 포함
- **결정 이유**: Pass 1+2를 모두 완료한 뒤 lint를 한 번만 실행하는 구조로 설계. Pass 2가 성공해도(스텁 없는 날) lint/graphify가 실행되도록 조건을 `ok>0 || pass2_ok=true`로 통합
- **트레이드오프**: watch-ingest.sh의 lock을 확인하지 않아 동시 실행 가능. 에이전트 호출이 직렬이므로 실질적 충돌 위험 낮음. wiki-inbox/에 파일이 있으면 Pass 2의 raw/ fallback이 다음 실행으로 밀림 (의도된 동작)
- **결론**: 2개 wiki에 정상 배포. daily-rescan launchd job 등록 완료(07/10/13/16/19/21시)