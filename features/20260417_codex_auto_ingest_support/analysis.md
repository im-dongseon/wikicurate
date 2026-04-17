# Analysis: Codex 자동 ingest 지원

- **Feature ID:** `20260417_codex_auto_ingest_support`
- **작업 시작일:** 2026-04-17
- **상태:** Step 1 — Analysis (완료)

---

## 배경 및 목적

현재 자동 ingest watcher는 `claude`, `gemini`만 지원하며 기본값도 `claude`다.
운영자가 자동 수집을 Codex CLI로 실행하고 싶어도 watcher가 `codex` 바이너리를 찾지 못하거나,
Codex가 슬래시 커맨드를 직접 실행하지 못해 자동화가 불안정하다.

본 Feature의 목적은 자동 ingest 기본 실행기를 `codex`로 변경하고,
Codex 비대화형 실행 흐름에 맞게 watcher와 운영 문서를 정합성 있게 개정하는 것이다.

---

## 현행 진단

| 항목 | 현황 | 근거 |
|------|------|------|
| 기본 에이전트 | `claude` | `scripts/watch-ingest.sh` |
| 지원 에이전트 | `claude`, `gemini`만 지원 | `select_agent_cmd()` case |
| launchd PATH 주입 | `codex` 경로 미수집 | `scripts/watcher.sh` |
| 자동화 프롬프트 방식 | slash command 직접 전달 | `"/ingest $file"`, `"/lint"` |
| 운영 문서 | Claude 중심 표현 다수 존재 | `_system/wiki-schema.md`, `README*.md` |

### 결함 목록

1. `WIKICURATE_AGENT=codex`를 지정해도 watcher가 실행기를 선택하지 못한다.
2. launchd 환경에서 `codex` 바이너리 경로가 PATH에 주입되지 않을 수 있다.
3. Codex는 slash command를 네이티브로 실행하지 않으므로 직접 프롬프트 전달 방식이 필요하다.
4. 문서가 실제 지원 상태와 어긋나 운영자가 잘못 설정할 위험이 있다.

---

## 개정 범위 결정

| 대상 파일 | 변경 성격 |
|-----------|-----------|
| `scripts/watch-ingest.sh` | 수정 — Codex 기본값/지원 추가, Codex용 프롬프트 분기 |
| `scripts/watcher.sh` | 수정 — PATH 주입 대상에 `codex` 추가 |
| `_system/wiki-schema.md` | 수정 — 에이전트 중립 표현 및 비-slash 환경 안내 보강 |
| `README.md` | 수정 — 기본 에이전트 설정 예시와 지원 에이전트 문구 갱신 |
| `README.en.md` | 수정 — 영문 운영 문서 정합성 갱신 |

`deploy.sh` 구조 변경은 불필요하다.

---

## 이 Feature의 성공 기준 (Definition of Done)

- [ ] 자동 ingest watcher 기본 에이전트가 `codex`로 변경된다
- [ ] `WIKICURATE_AGENT=codex`일 때 watcher가 `codex` CLI를 선택할 수 있다
- [ ] launchd 환경에서 `codex` 실행 경로가 PATH에 포함된다
- [ ] Codex 자동 실행 시 `/ingest`, `/lint` 대신 playbook 기반 프롬프트를 사용한다
- [ ] 기존 `claude`, `gemini` fallback은 유지된다
- [ ] 운영 문서가 Codex 기본값과 비-slash 실행 방식을 반영한다
