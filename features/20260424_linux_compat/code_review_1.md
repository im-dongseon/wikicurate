# Code Review 1: Linux 호환성 지원 (20260424_linux_compat)

- **리뷰어**: Claude (Sonnet 4.6, 컨텍스트 초기화)
- **리뷰 일자**: 2026-04-24
- **리뷰 대상**: `deploy.sh`, `scripts/watcher.sh`, `scripts/watch-ingest.sh`, `scripts/daily-rescan.sh`

---

## DoD 체크리스트 결과

| 항목 | 결과 | 비고 |
|------|------|------|
| design.md의 모든 변경 항목이 반영됨 | PASS (부분 주의) | [D-01] 참조 |
| macOS 기존 동작 경로에 회귀 없음 | PASS | macOS 분기 보존 확인 |
| Linux 분기 로직의 정확성 (systemd unit, inotifywait 옵션) | PASS (경미 주의) | [B-01], [B-02] 참조 |
| md5_short() 함수가 모든 사용처에서 교체됐는지 확인 | PASS | 정의 1 + 호출 5 = 총 6곳, design.md 명세와 일치 |
| pkg_install_hint() 함수의 brew 메시지 대체 누락 없음 | PASS | 4개 파일 전체 적용 확인 |
| _system/ 내 기존 파일과 충돌 없음 | PASS | _system/ 변경 없음 |
| 결함 처리 완료 여부 | 조건부 — 아래 결함 목록 참조 | |

---

## 결함 목록

### [B-01] 심각도: 낮음 — `watcher.sh` register에 `inotifywait` 의존성 체크 누락

**파일**: `scripts/watcher.sh` (register 블록)

**문제**: `register` 진입부에서 `yq`, `sqlite3`만 의존성 체크하고, `inotifywait` (Linux) / `fswatch` (macOS)는 체크하지 않는다. 결과적으로 Linux에서 `inotifywait`가 미설치된 상태에서 `watcher.sh register`를 실행하면 systemd 서비스 등록까지는 성공하지만, 서비스 기동 시 `watch-ingest.sh`가 즉시 에러 종료한다. 사용자는 서비스 등록 성공 메시지를 보았으나 실제로는 동작하지 않는 상태가 된다.

**현재 코드** (`scripts/watcher.sh`, 34~42행):
```bash
if ! command -v yq > /dev/null 2>&1; then
    echo "ERROR: yq 미설치. '$(pkg_install_hint yq)' 후 재시도하세요." >&2
    exit 1
fi
if ! command -v sqlite3 > /dev/null 2>&1; then
    echo "ERROR: sqlite3 미설치. '$(pkg_install_hint sqlite3)' 후 재시도하세요." >&2
    exit 1
fi
# fswatch / inotifywait 체크 없음
```

**권고 수정**:
```bash
if [ "$OS" = "Darwin" ]; then
    if ! command -v fswatch > /dev/null 2>&1; then
        echo "ERROR: fswatch 미설치. '$(pkg_install_hint fswatch)' 후 재시도하세요." >&2
        exit 1
    fi
else
    if ! command -v inotifywait > /dev/null 2>&1; then
        echo "ERROR: inotifywait 미설치. '$(pkg_install_hint inotify-tools)' 후 재시도하세요." >&2
        exit 1
    fi
fi
```

**영향 범위**: Linux 신규 설치 경험. macOS 회귀 없음.

---

### [B-02] 심각도: 낮음 — `inotifywait --exclude` 정규식의 `~` 앵커 불일치

**파일**: `scripts/watch-ingest.sh` (256~260행)

**문제**: fswatch와 inotifywait의 tilde(`~`) 파일 제외 패턴이 의미상 다르다.

- fswatch: `--exclude '.*~$'` → 경로가 `~`로 **끝나는** 파일만 제외 (vim 백업 파일 정확히 타깃)
- inotifywait: `--exclude '(\.DS_Store|\.swp|~|/error/)'` → 경로에 `~`가 **포함된** 모든 경로 제외

이로 인해 `~`를 포함하는 디렉토리 이름(예: `~/notes/project~backup/`)에 존재하는 정상 파일도 모니터링에서 제외될 수 있다.

**권고 수정** (inotifywait --exclude 패턴을 fswatch와 동등하게):
```bash
--exclude '(\.DS_Store$|\.swp$|~$|/error/)'
```

**영향 범위**: 경로에 `~`가 포함된 디렉토리를 wiki-inbox로 사용하는 경우 이벤트 누락. 일반적인 환경에서는 해당 없음. macOS 회귀 없음.

---

### [D-01] 심각도: 정보 — design.md `inotifywait` 이벤트 누락 (`-e modify`)

**파일**: `scripts/watch-ingest.sh` (256~260행)

**관찰**: fswatch는 `--event Updated`를 포함하지만, inotifywait 분기는 `-e create -e moved_to`만 사용하고 `-e modify`(또는 `-e close_write`)가 없다.

**기능적 영향 없음**: watch-ingest.sh의 큐 파일은 처리 트리거 신호(non-empty)로만 활용되며, 실제 ingest 대상 파일 목록은 `find "$inbox_dir" -maxdepth 1`로 직접 스캔한다. 따라서 이미 inbox에 존재하는 파일의 수정 이벤트가 큐에 기록되지 않아도, 다음 `$INTERVAL`(기본 600초) 주기에 `file_count > 0` 조건으로 인해 처리된다.

**실질적 차이**: 파일이 수정만 되고 새로 생성되지 않은 경우, 최대 `$INTERVAL`(기본 10분)의 처리 지연이 발생할 수 있다. 이는 design.md의 설계 근거("queue 파일은 '변경 발생' 신호로만 사용됨")에 의해 의도된 트레이드오프다.

**조치 필요 여부**: 설계 범위 내 트레이드오프이므로 현 릴리스에서 필수 수정 대상 아님. 향후 실시간 반응성 개선이 필요할 경우 `-e close_write` 추가를 별도 Feature로 검토 권장.

---

## 세부 검토 결과

### 1. Linux 분기 로직 정확성

| 구성요소 | 검토 결과 |
|---------|----------|
| `systemd --user` 서비스 단위 파일 구조 | 정확 (`[Unit]`, `[Service]`, `[Install]` 섹션 완전) |
| `Type=simple` + `Restart=always` | 올바른 long-running daemon 설정 |
| `Type=oneshot` (rescan service) | 올바름 |
| `OnCalendar=*-*-* 07,10,13,16,19,21:00:00` | 유효한 systemd 타이머 문법 |
| `Persistent=true` | 누락된 실행 자동 복구에 필요, 올바르게 포함됨 |
| `StandardOutput=append:` | systemd 240+ 필요; Ubuntu 22.04 (systemd 249) 충족 |
| `systemctl --user enable --now` | 활성화+즉시 기동 조합, 올바름 |
| `loginctl enable-linger` 안내 메시지 | 미결 사항 해소 확인 (207~208행) |

### 2. macOS 회귀 검증

- `watcher.sh`: launchd 전체 로직이 `if [ "$OS" = "Darwin" ]` 블록으로 완전히 보존됨
- `watch-ingest.sh`: fswatch 호출이 Darwin 분기 내에서 그대로 유지됨 (244~254행)
- `deploy.sh`: 기존 macOS 전용 로직 변경 없음; pkg_install_hint가 Darwin에서 동일하게 `brew install` 반환
- `daily-rescan.sh`: 단순 메시지 치환이며 로직 변경 없음

### 3. pkg_install_hint 적용 완전성

4개 파일 모두 함수 정의 및 호출 확인:

| 파일 | 함수 정의 | 호출 위치 |
|------|----------|----------|
| `deploy.sh` | 8행 | 26행 (yq) |
| `scripts/watcher.sh` | 9행 | 35행 (yq), 39행 (sqlite3) |
| `scripts/watch-ingest.sh` | 7행 | 34행 (yq), 40행 (fswatch), 45행 (inotify-tools), 51행 (sqlite3) |
| `scripts/daily-rescan.sh` | 7행 | 24행 (yq) |

누락 없음.

### 4. md5_short() 교체 완전성

`scripts/watch-ingest.sh` 내 md5_short 위치:
- 16~21행: 함수 정의 (Darwin: `md5`, Linux: `md5sum`)
- 210행: `cleanup()` 내
- 219행: startup stale lock 정리 루프
- 239행: fswatch/inotifywait 기동 루프
- 289행: sleep 후 stale lock 재정리 루프
- 303행: 공유 타이머 루프

총 5개 호출처 전환 완료. 함수 외부에 `| md5 |` 패턴 잔존 없음.

### 5. set -euo pipefail 환경에서 command substitution 안전성

`echo "... '$(pkg_install_hint yq)' ..."` 패턴은 다음 이유로 안전하다:
- `pkg_install_hint`는 `if/else/echo`만 포함하며 항상 exit 0으로 종료
- command substitution의 반환값은 `echo`의 인자로 쓰이므로 set -e 트리거 대상이 아님
- bash 4.4+ 기준 command substitution 내 실패는 set -e를 전파하지 않음(Ubuntu 22.04 기본 bash 5.1)

---

## 종합 판정

**결과**: 조건부 통과 (minor defects)

- **[B-01]** (`watcher.sh` register의 `inotifywait` 의존성 체크 누락): Step 3 복귀 후 수정 권장. 서비스 등록 후 무증상 실패 케이스를 방지.
- **[B-02]** (`inotifywait --exclude` 앵커 불일치): 선택적 수정. 일반 환경에서 영향 없으나, 정확성 측면에서 수정 권장.
- **[D-01]** (inotifywait `-e modify` 미포함): 현 설계 범위 내 트레이드오프로 수용. 별도 Feature 검토 권장.

[B-01]만 수정하면 나머지 항목은 모두 충족. [B-01] 수정 후 재배포 가능.
