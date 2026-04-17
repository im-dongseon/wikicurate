# Design: fswatch 기반 자동 ingest

- **Feature ID:** `20260417_fswatch_auto_ingest`
- **작업 시작일:** 2026-04-17
- **상태:** Step 2 — Design

---

## 개정 전/후 비교 (Before → After)

| 항목 | Before | After |
|------|--------|-------|
| ingest 트리거 | 사용자 수동 실행 | `raw/` 변경 감지 시 10분 이내 자동 실행 |
| 감시 대상 | 없음 | `.env`의 `DEPLOY_PATHS` 전체 (`<root>/raw/`) |
| 에이전트 선택 | 사용자가 직접 선택 | `WIKICURATE_AGENT` 환경변수 (기본: `claude`) |
| 권한 프롬프트 | 매 실행마다 승인 요청 | 권한 우회 플래그로 완전 비블로킹 |
| 실행 방식 | 동기 (포그라운드) | 비동기 (백그라운드 서브셸) |
| 초기 설정 흐름 | `deploy.sh` → 수동 watcher 기동 | `deploy.sh` → watcher 자동 등록 |
| watcher 관리 | 없음 | `scripts/watcher.sh register/unregister/status` |

---

## 대상 파일 및 변경 성격

| 파일 | 변경 성격 |
|------|-----------|
| `scripts/watch-ingest.sh` | **신규 추가** — fswatch + 타이머 루프 |
| `scripts/watcher.sh` | **신규 추가** — launchd 등록/해제/상태 관리 |
| `deploy.sh` | **수정** — 마지막 단계에 `watcher.sh register` 호출 추가 |

`_system/` 내 파일 변경 없음.

---

## 전체 흐름

### 초기 설정 (한 번)

```
./deploy.sh
    │
    ├── 1. _system/ → 각 DEPLOY_PATH 동기화      (기존)
    ├── 2. 심볼릭 링크 생성                        (기존)
    ├── 3. .claude/settings.json 배포              (기존)
    └── 4. scripts/watcher.sh register             (신규)
              │
              └── launchd plist 생성 + launchctl load
                  → 로그인 시 자동 시작, 크래시 시 자동 재시작
```

### 이후 상시 동작

```
[launchd] watch-ingest.sh 상시 실행
    │
    ├─ DEPLOY_PATH A/raw/: fswatch ──► QUEUE_A 누적
    ├─ DEPLOY_PATH B/raw/: fswatch ──► QUEUE_B 누적
    └─ DEPLOY_PATH C/raw/: fswatch ──► QUEUE_C 누적
                │
        [600초마다 타이머]
                │
                └─ 큐 있는 루트: drain → cd <root> → agent "/ingest <file>" (&)
```

### 독립 관리 (필요 시)

```bash
./scripts/watcher.sh register    # 등록 (이미 등록돼 있으면 재등록)
./scripts/watcher.sh unregister  # 해제 + plist 삭제
./scripts/watcher.sh status      # 실행 상태 확인
```

---

## 아키텍처 설계

### KMS 루트 소스: `.env`의 `DEPLOY_PATHS`

`deploy.sh`와 동일한 패턴으로 `.env`를 로드해 `DEPLOY_PATHS`를 KMS 루트 목록으로 사용한다.
각 루트에 `raw/`가 없으면 경고 후 건너뜀.

### 임시 파일 정의

| 항목 | 경로 | 설명 |
|------|------|------|
| `QUEUE_FILE` | `/tmp/wikicurate-<root_hash>.queue` | 루트별 변경 파일 경로 누적 |
| `LOCK_FILE` | `/tmp/wikicurate-<root_hash>.lock` | 루트별 중복 실행 방지 |
| 로그 | `/tmp/wikicurate-watcher.log` | launchd stdout/stderr |

> `<root_hash>`: 루트 절대경로의 MD5 앞 8자리 — 공백 포함 경로 안전 처리

---

## 스크립트 설계

### 1. `scripts/watch-ingest.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT="${WIKICURATE_AGENT:-claude}"
INTERVAL="${WIKICURATE_INTERVAL:-600}"

# .env 로드
source "$SCRIPT_DIR/.env"

# 사전 검증
command -v fswatch > /dev/null 2>&1 || { echo "ERROR: fswatch 미설치"; exit 1; }

# 에이전트 선택 (claude → gemini 순 fallback)
select_agent_cmd() {
    local candidates=("$1" claude gemini)
    local seen=()
    for agent in "${candidates[@]}"; do
        [[ " ${seen[*]} " == *" $agent "* ]] && continue
        seen+=("$agent")
        case "$agent" in
            claude) command -v claude > /dev/null 2>&1 && echo "claude --dangerously-skip-permissions -p" && return 0 ;;
            gemini) command -v gemini > /dev/null 2>&1 && echo "gemini --yolo -p" && return 0 ;;
        esac
    done
    echo "ERROR: 사용 가능한 에이전트 없음" >&2; return 1
}

AGENT_CMD=$(select_agent_cmd "$AGENT") || exit 1

# 종료 시 정리
cleanup() {
    for root in "${DEPLOY_PATHS[@]}"; do
        h=$(echo "$root" | md5 | cut -c1-8)
        rm -f "/tmp/wikicurate-${h}.queue" "/tmp/wikicurate-${h}.lock"
    done
    kill 0 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# 시작 시 스테일 lock 파일 정리 (이전 SIGKILL/비정상 종료 대비)
for root in "${DEPLOY_PATHS[@]}"; do
    h=$(echo "$root" | md5 | cut -c1-8)
    rm -f "/tmp/wikicurate-${h}.lock"
done

# 루트별 fswatch 기동
for root in "${DEPLOY_PATHS[@]}"; do
    raw_dir="$root/raw"
    [ -d "$raw_dir" ] || { echo "[SKIP] raw/ 없음: $root"; continue; }
    h=$(echo "$root" | md5 | cut -c1-8)
    touch "/tmp/wikicurate-${h}.queue"
    fswatch --event Created --event Updated --event MovedTo \
        --latency 1 \
        --exclude '.*\.DS_Store$' --exclude '.*\.swp$' --exclude '.*~$' \
        "$raw_dir" >> "/tmp/wikicurate-${h}.queue" &
    echo "[감시 시작] $raw_dir"
done

# 공유 타이머 루프
while true; do
    sleep "$INTERVAL"
    for root in "${DEPLOY_PATHS[@]}"; do
        h=$(echo "$root" | md5 | cut -c1-8)
        queue="/tmp/wikicurate-${h}.queue"
        lock="/tmp/wikicurate-${h}.lock"
        [ -f "$queue" ] && [ -s "$queue" ] || continue
        if [ -f "$lock" ]; then
            echo "[$(date +%H:%M:%S)] 실행 중 — 연기: $(basename "$root")"; continue
        fi
        # 원자적 큐 drain: mv로 먼저 분리 후 처리 (fswatch 경쟁 조건 방지)
        mv "$queue" "${queue}.tmp"
        touch "$queue"
        changed=$(sort -u "${queue}.tmp")
        rm -f "${queue}.tmp"
        echo "[$(date +%H:%M:%S)] 변경 감지 → ingest: $(basename "$root")"
        (
            touch "$lock"; trap 'rm -f "$lock"' EXIT
            while IFS= read -r file; do
                [ -f "$file" ] || continue
                echo "  → $(basename "$file")"
                (cd "$root" && $AGENT_CMD "/ingest $file")
            done <<< "$changed"
        ) &
    done
done
```

---

### 2. `scripts/watcher.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST_LABEL="com.wikicurate.ingest-watcher"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
WATCHER="$SCRIPT_DIR/scripts/watch-ingest.sh"

case "${1:-}" in
register)
    # launchd는 제한된 PATH에서 실행되므로 등록 시점에 실제 바이너리 경로를 수집
    # (예: claude는 /Applications/cmux.app/Contents/Resources/bin/ 등 비표준 위치)
    RESOLVED_DIRS=""
    for bin in fswatch claude gemini; do
        bin_path=$(command -v "$bin" 2>/dev/null || true)
        if [ -n "$bin_path" ]; then
            bin_dir=$(dirname "$bin_path")
            # 중복 없이 추가
            case ":${RESOLVED_DIRS}:" in
                *":${bin_dir}:"*) ;;
                *) RESOLVED_DIRS="${RESOLVED_DIRS:+${RESOLVED_DIRS}:}${bin_dir}" ;;
            esac
        fi
    done
    INJECTED_PATH="${RESOLVED_DIRS}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    # 이미 등록돼 있으면 먼저 해제 (idempotent)
    launchctl unload "$PLIST_PATH" 2>/dev/null || true

    cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${WATCHER}</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>${INJECTED_PATH}</string>
    </dict>
    <key>WorkingDirectory</key>
    <string>${SCRIPT_DIR}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/wikicurate-watcher.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/wikicurate-watcher.log</string>
</dict>
</plist>
EOF

    launchctl load "$PLIST_PATH"
    echo "✓ ingest-watcher 등록 완료"
    echo "  주입된 PATH: $INJECTED_PATH"
    echo "  로그: tail -f /tmp/wikicurate-watcher.log"
    ;;

unregister)
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
    echo "✓ ingest-watcher 해제 완료"
    ;;

status)
    if launchctl list | grep -q "$PLIST_LABEL"; then
        echo "● 실행 중 ($PLIST_LABEL)"
        launchctl list "$PLIST_LABEL" 2>/dev/null || true
    else
        echo "○ 미등록 또는 중지 상태"
    fi
    ;;

*)
    echo "Usage: $0 {register|unregister|status}"
    exit 1
    ;;
esac
```

---

### 3. `deploy.sh` 수정 (추가 부분만)

```bash
# 기존 deploy_to() 루프 이후 마지막에 추가
echo "========================================"
echo "ingest-watcher 등록 중..."
"$SCRIPT_DIR/scripts/watcher.sh" register
```

---

## 에이전트별 실행 명령 정리

| 에이전트 | 실행 형태 |
|----------|-----------|
| Claude | `claude --dangerously-skip-permissions -p "/ingest <file>"` |
| Gemini | `gemini --yolo -p "/ingest <file>"` |

---

## 연계 룰/스킬 정합성 검토

| 연계 대상 | 검토 결과 |
|-----------|-----------|
| `.env` / `DEPLOY_PATHS` | `deploy.sh`와 동일 패턴으로 로드 — 관리 일원화 |
| `deploy.sh` | 마지막 단계에 `watcher.sh register` 1줄 추가만으로 연동 |
| `_system/commands/ingest.md` | `$ARGUMENTS`로 파일 경로 전달 — 호환 |
| `_system/commands/setup.md` | watcher 등록은 `deploy.sh` 단계에서 완료 — setup과 무관 |
| `wiki/log.md` | 에이전트가 append — 스크립트 간섭 없음 |

---

## 견고성 개선 사항 (반영 완료)

| # | 문제 | 해결 방식 | 위치 |
|---|------|-----------|------|
| 1 | 큐 drain 레이스 컨디션 | `mv queue queue.tmp` → 처리 후 삭제 | `watch-ingest.sh` 타이머 루프 |
| 2 | launchd 제한 PATH | 등록 시점에 실제 바이너리 경로 수집 → plist `EnvironmentVariables`에 주입 | `watcher.sh register` |
| 3 | 비정상 종료 후 스테일 lock | 스크립트 기동 시 기존 lock 파일 일괄 삭제 | `watch-ingest.sh` 초기화 블록 |

## 미결 사항 (Unresolved Issues)

없음.
