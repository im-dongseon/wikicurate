# Analysis: ingest 완료 후 자동 lint 실행

- **Feature ID:** `20260417_auto_lint_after_ingest`
- **작업 시작일:** 2026-04-17
- **상태:** Step 1 — Analysis

---

## 배경 및 목적

현재 `/ingest`는 fswatch 기반으로 자동 실행되지만, `/lint`는 수동 실행만 가능하다.
ingest는 wiki 페이지를 생성·수정하므로 완료 직후가 lint 실행의 자연스러운 시점이다.
lint를 자동화하면 고아 페이지, 끊긴 링크, 모순 클레임 등의 구조적 문제를 변경 즉시 감지·수정할 수 있다.

## 현행 진단

| 항목 | 현재 상태 | 문제 |
|------|-----------|------|
| `/lint` 실행 | 수동 | 사용자가 직접 실행하지 않으면 누락됨 |
| ingest 완료 후 처리 | 성공/실패 카운트 로그만 남김 | lint 트리거 없음 |
| `watch-ingest.sh` 구조 | 파일별 ingest 후 배치 완료 로그 | lint 삽입 지점 명확히 존재 |

### lint 커맨드 특성

- wiki 전체를 대상으로 고아 페이지·끊긴 링크·모순 클레임 탐지 및 자동 수정
- 완료 후 `/graphify --update`로 graph.json 갱신
- `wiki/log.md`에 결과 기록
- 실행 시간이 길 수 있음 (wiki 규모에 비례)

## 개정 범위 결정

| 파일 | 변경 성격 | 사유 |
|------|-----------|------|
| `scripts/watch-ingest.sh` | 수정 | ingest 배치 완료 후 lint 트리거 추가 |
| `scripts/watcher.sh` | 변경 없음 | launchd 등록 로직과 무관 |
| `_system/commands/lint.md` | 변경 없음 | lint 커맨드 자체 변경 없음 |
| `deploy.sh` | 변경 없음 | 배포 흐름 무관 |

### 설계 결정 사항

**트리거 조건:** 배치 내 ingest 성공 건수 > 0일 때만 lint 실행
- 전부 실패한 경우 wiki 변경이 없으므로 lint 불필요

**실행 위치:** 기존 ingest 서브셸 내부 (ingest 루프 완료 후)
- 기존 lock을 공유하므로 ingest와 lint가 동시에 실행되는 경쟁 조건 없음
- lint가 완료되어야 lock이 해제 → 다음 ingest 주기는 lint 종료 후 시작 (의도된 동작)

**비동기 여부:** 기존 서브셸이 이미 `&`로 비동기 실행 중이므로 추가 분리 불필요

**실패 처리:** lint 실패를 로그에 기록하되 ingest 결과에는 영향 없음

## 이 Feature의 성공 기준 (Definition of Done)

- [ ] ingest 배치에서 1개 이상 성공 시 lint가 자동 실행됨
- [ ] lint 성공/실패가 watcher.log에 기록됨
- [ ] lint 실패 시 에러 출력이 로그에 남음
- [ ] lint 실패가 ingest 성공 카운트에 영향을 주지 않음
- [ ] 전체 ingest 실패 시 lint가 실행되지 않음
