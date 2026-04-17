# Design: Codex 자동 ingest 지원

- **Feature ID:** `20260417_codex_auto_ingest_support`
- **작업 시작일:** 2026-04-17
- **상태:** Step 2 — Design

---

## 개정 전/후 비교 (Before → After)

| 항목 | Before | After |
|------|--------|-------|
| 기본 에이전트 | `claude` | `codex` |
| 지원 에이전트 | `claude`, `gemini` | `codex`, `claude`, `gemini` |
| Codex PATH 주입 | 미지원 | launchd 등록 시 자동 수집 |
| Codex 실행 방식 | 없음 | `codex exec` 비대화형 실행 |
| 자동 프롬프트 | slash command 직접 전달 | Codex는 playbook 기반 자연어 프롬프트 사용 |
| 운영 문서 | Claude 중심 표현 일부 존재 | 에이전트 중립 + Codex 기본값 명시 |

---

## 대상 파일 및 변경 성격

| 파일 | 변경 성격 |
|------|-----------|
| `scripts/watch-ingest.sh` | 수정 |
| `scripts/watcher.sh` | 수정 |
| `_system/wiki-schema.md` | 수정 |
| `README.md` | 수정 |
| `README.en.md` | 수정 |

---

## 구현 설계

### 1. `scripts/watch-ingest.sh`

- `AGENT="${WIKICURATE_AGENT:-codex}"`로 기본값 변경
- 에이전트 후보 순서를 `("$1" codex claude gemini)`로 변경
- `codex` case 추가
  - 비대화형 명령: `codex exec -a never -s workspace-write --skip-git-repo-check`
- `build_agent_prompt()` 헬퍼 추가
  - `codex + ingest`: `_system/commands/ingest.md`를 읽고 지정 파일에 대해 실행하라는 프롬프트 생성
  - `codex + lint`: `_system/commands/lint.md`를 읽고 실행하라는 프롬프트 생성
  - 나머지 에이전트는 기존 slash command 문자열 유지
- ingest/lint 실행부에서 `build_agent_prompt` 반환값을 사용

### 2. `scripts/watcher.sh`

- PATH 수집 대상 바이너리 목록을 `fswatch codex claude gemini sqlite3`로 확장

### 3. `_system/wiki-schema.md`

- 문서 헤더의 Claude 전용 표현을 중립적으로 완화
- slash command 안내는 유지하되, 비-slash 환경에서 `_system/commands/*.md` playbook을 읽어 실행한다는 규칙을 더 명확히 유지
- graphify 설명 중 특정 에이전트명 하드코딩 제거

### 4. `README.md` / `README.en.md`

- `.env` 예시에 `WIKICURATE_AGENT=codex` 추가
- 지원 에이전트 목록에 Codex CLI 추가
- 자동 watcher 기본 실행기가 Codex라는 점을 명시

---

## 연계 룰/스킬 정합성 검토

- `_system/commands/ingest.md`, `_system/commands/lint.md`는 그대로 재사용한다.
- `deploy.sh`는 watcher 등록만 담당하므로 수정 없이 호환된다.
- 기존 Claude/Gemini 경로는 fallback으로 유지되어 하위 호환성을 해치지 않는다.

---

## 미결 사항 (Unresolved Issues)

없음
