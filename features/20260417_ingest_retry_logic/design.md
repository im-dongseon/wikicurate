# Design: SQLite 기반 ingest 재시도 및 에러 격리 시스템

- **Feature ID:** `20260417_ingest_retry_logic`
- **상태:** Step 2 — Design (Pending Approval)

---

## 개정 전/후 비교 (Before → After)

| 항목 | Before | After |
|------|--------|-------|
| 실패 처리 | 로그 기록 후 해당 파일 스킵 | SQLite DB에 기록 후 다음 주기 재시도 |
| 재시도 관리 | 없음 (수동) | 최대 5회 자동 재시도 |
| 최종 실패 | `raw/`에 방치 | `raw/error/` 폴더로 자동 격리 |
| 의존성 | `fswatch`, `agent` | `fswatch`, `agent`, **`sqlite3`** |

---

## 데이터베이스 설계 (SQLite)

- **파일 위치:** `$root/_state/data/wikicurate-retries.db`
  - `$root`는 각 DEPLOY_PATH (루트별 독립 DB)
  - `/tmp` 대신 영속 경로 사용 — 재부팅 후에도 재시도 상태가 보존됨
  - `_state/data/` 디렉토리는 초기화 단계에서 자동 생성 (`mkdir -p`)
  - `_state/`는 `deploy.sh`의 rsync 대상이 아니므로 배포 시 덮어쓰기 위험 없음
  - `_system/`과 동일한 `_` 접두사 컨벤션 — Obsidian에서 시스템 폴더로 구분 가능
  - Obsidian 사용 시 `_state/`를 "제외 폴더"로 설정하면 검색·그래프 뷰에서 숨김 처리 가능
    (설정 → Files & Links → Excluded files)
- **WAL 모드:** DB 초기화 시 `PRAGMA journal_mode=WAL;` 실행
  - 다수의 루트(서브셸)가 동시에 쓰기를 시도할 때 lock 충돌 방지
- **Busy Timeout:** 모든 `sqlite3` CLI 호출 시 `PRAGMA busy_timeout=5000;`을 쿼리 서두에 적용
  - WAL 모드라도 극히 짧은 간격의 동시 쓰기 시 `database is locked` 오류 가능
  - `sqlite3` CLI의 기본 busy_timeout은 0이므로 명시적으로 5초 대기 설정
  - `.timeout N` 방식은 일부 sqlite3 CLI 버전에서 인자로 직접 받지 못할 수 있으므로 PRAGMA 방식 사용
  - 호출 형식: `sqlite3 "$DB_PATH" "PRAGMA busy_timeout=5000; SQL_QUERY;"`

- **테이블 스키마:**
```sql
CREATE TABLE IF NOT EXISTS ingest_retries (
    filepath TEXT PRIMARY KEY,
    retry_count INTEGER DEFAULT 0,
    last_error TEXT,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```
  - `root_path` 컬럼 불필요 — DB가 루트별로 분리되어 있으므로

- **`retry_count` 의미:** 재시도 횟수 (0-based)
  - `0`: 첫 실패 직후 기록, 아직 재시도 미실시
  - `1`~`4`: 해당 횟수만큼 재시도했으나 모두 실패
  - `>= 5`: 5회 재시도 모두 실패 → 격리 조건 충족
  - 총 시도 횟수: 최초 1회 + 재시도 최대 5회 = 최대 6회
- **로그 출력 형식 (재시도 시):**
  - `[RETRY 1/5] filename.md` — retry_count가 1 이상인 파일을 처리할 때 출력
  - `[FAIL] filename.md` — 최초 실패(retry_count=0 기록 직후) 출력
  - `[ISOLATED] raw/error/filename.20260417_153000.md` — 격리 완료 시 출력

---

## 로직 변경 상세 (`scripts/watch-ingest.sh`)

### 1. 초기화 단계 (스크립트 시작 시 1회)
- `sqlite3` 존재 여부 확인. 없으면 에러 후 종료.
  - launchd 재기동 등으로 `watch-ingest.sh` 자체가 실행되는 시점에도 검사하여,
    등록 이후 sqlite3가 제거된 경우에도 즉시 감지.
- 각 `root`별로 `mkdir -p "$root/_state/data"` 실행.
- DB 파일 생성 및 `ingest_retries` 테이블 자동 생성.
- `PRAGMA journal_mode=WAL;` 적용.

### 2. 처리 루프 (`while true`) — **메인 루프**에서 실행

각 루트 처리 전, 서브셸 진입 이전에:

1. `queue` 파일을 `queue.tmp`로 분리 (원자적 drain, 기존 로직 유지).
2. `queue.tmp`에서 변경 목록(`fswatch_list`) 추출.
3. 해당 루트의 DB (`$root/_state/data/wikicurate-retries.db`)에서 재시도 대기 파일 조회:
   ```sql
   SELECT filepath FROM ingest_retries;
   ```
4. **유령 레코드 청소:** DB 조회 결과 중 파일이 실제로 존재하지 않는 항목 삭제.
   - `[ -f "$file" ]` 체크 후 파일 없으면:
     ```sql
     DELETE FROM ingest_retries WHERE filepath = ?;
     ```
   - 사용자가 `raw/`에서 파일을 수동 삭제/이동한 경우 DB에 유령 레코드가 남지 않도록 함.
5. `fswatch_list`와 유효한 DB 조회 결과를 병합 후 `sort -u`로 중복 제거 → `changed` 목록 확정.
6. 확정된 `changed`를 서브셸에 전달하여 비동기 실행.

> **이유:** DB 조회를 메인 루프에서 처리하여 서브셸 간 동시 조회 충돌을 방지하고, 같은 파일이 여러 서브셸에 중복 배분되는 것을 막음.

### 3. 처리 결과 후속 조치 — **서브셸 내부**에서 실행

파일 처리 전, retry_count 조회로 재시도 여부 및 로그 메시지 결정:
- `retry_count = 0`: `[FAIL]` 출력 (최초 실패)
- `retry_count >= 1`: `[RETRY N/5]` 출력 (N = retry_count)

- **성공 시:**
  ```sql
  DELETE FROM ingest_retries WHERE filepath = ?;
  ```

- **실패 시:** UPSERT로 원자적 처리:
  ```sql
  INSERT INTO ingest_retries (filepath, retry_count, last_error, updated_at)
    VALUES (?, 0, ?, CURRENT_TIMESTAMP)
  ON CONFLICT(filepath) DO UPDATE SET
    retry_count = retry_count + 1,
    last_error  = excluded.last_error,
    updated_at  = CURRENT_TIMESTAMP;
  ```
  - UPSERT 후 `retry_count`를 조회하여 격리 여부 판단:
    ```sql
    SELECT retry_count FROM ingest_retries WHERE filepath = ?;
    ```
  - `retry_count >= 5` 인 경우 (5회 재시도 모두 실패):
    1. 해당 루트의 `raw/error/` 디렉토리 확인 (없으면 생성).
    2. **파일명 충돌 처리 — 확장자 보존:** 대상 경로에 동일 파일명이 존재하면 타임스탬프를
       확장자 앞에 삽입하여 원본 확장자를 유지.
       예) `note.md` → `note.20260417_153000.md`
       예) `report` (확장자 없음) → `report.20260417_153000`
    3. 파일을 `raw/error/`로 이동 (`mv`).
    4. DB에서 해당 레코드 삭제.
    5. `[ISOLATED] raw/error/격리된파일명` 출력.

### 4. DB 호출 에러 처리

모든 sqlite3 호출은 헬퍼 함수를 통해 실행하며, 실패 시 아래 규칙을 따른다.

- sqlite3 stderr를 변수로 캡처 후 exit code 확인.
- 비정상 종료(`rc != 0`) 시 `[DB ERROR] (rc=N) <에러 메시지>`를 스크립트 stderr로 출력.
- 스크립트 stderr는 launchd를 통해 `/tmp/wikicurate-watcher.log`에 자동 기록됨.
- 호출부에서 `|| { ... }` 패턴으로 실패 시 동작(스킵·격리 중단 등)을 명시적으로 분기.

```bash
# 헬퍼 함수 예시 (구현 참고)
db_exec() {
    local sql="$1"
    local err rc
    err=$(sqlite3 "$DB_PATH" "PRAGMA busy_timeout=5000; $sql" 2>&1)
    rc=$?
    [ $rc -ne 0 ] && echo "[DB ERROR] (rc=$rc) $err" >&2
    return $rc
}
```

---

## 의존성 검사 상세 (`scripts/watcher.sh`)

- `register` 시점에 `sqlite3` 바이너리 위치를 찾아 `PATH`에 주입.
  - 기존 `for bin in fswatch claude gemini` 루프에 `sqlite3` 추가.
- `sqlite3` 미설치 시 `PATH` 주입 불가 → 등록 중단 및 설치 안내 메시지 출력.

---

## 연계 룰/스킬 정합성 검토

- **재부팅 복원성:** DB가 `$root/_state/data/`에 있으므로 launchd 재기동 후에도 재시도 대기 파일이 유지됨.
- **루트별 격리:** DB가 루트마다 분리되어 있으므로 `root_path` 컬럼 불필요, 스키마 단순화.
- **동시성 안전:** WAL 모드 + Busy Timeout 5초 + UPSERT로 다수의 서브셸이 동시 쓰기해도 데이터 정합성 보장.
- **런타임 방어:** `watch-ingest.sh` 초기화 시 sqlite3 재검사로, 등록 후 sqlite3 제거 시에도 즉시 감지.
- **유령 레코드 방지:** 메인 루프의 파일 존재 검사로 수동 삭제된 파일이 DB에 잔류하지 않음.
- **Linux 호환성:** `sqlite3`는 대부분의 배포판에 기본 포함. `mv`, `mkdir -p`는 POSIX 표준.
- **성능:** SQLite 파일 기반으로 대량 파일에도 안정적. WAL 모드로 읽기/쓰기 경합 최소화.

---

## 미결 사항

- 없음.
