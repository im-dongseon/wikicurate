# Design: Linux 호환성 지원

approved: 2026-04-24

- **Feature ID**: 20260424_linux_compat
- **작성일**: 2026-04-24
- **접근 방식**: 단일 파일 내 OS 분기 (`uname -s` 감지)

---

## 공통 헬퍼 (각 파일 상단에 추가)

```bash
OS=$(uname -s)   # "Darwin" | "Linux"

pkg_install_hint() {          # brew 메시지 대체
    local pkg="$1"
    if [ "$OS" = "Darwin" ]; then
        echo "brew install $pkg"
    else
        echo "sudo apt-get install -y $pkg"
    fi
}

md5_short() {                 # md5 / md5sum 분기
    if [ "$OS" = "Darwin" ]; then
        echo "$1" | md5 | cut -c1-8
    else
        echo "$1" | md5sum | cut -c1-8
    fi
}
```

---

## 파일별 변경 Before → After

### 1. `scripts/watcher.sh`

**가장 큰 변경** — launchd 전체를 systemd user service로 대체

#### Before (macOS 전용)

```bash
PLIST_LABEL="com.wikicurate.ingest-watcher"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
# register: plist 생성 + launchctl load
# unregister: launchctl unload + rm plist
# status: launchctl list | grep
```

#### After (OS 분기)

```bash
if [ "$OS" = "Darwin" ]; then
    # 기존 launchd 로직 그대로 유지
else
    # Linux: systemd user service
    SYSTEMD_DIR="$HOME/.config/systemd/user"
    WATCHER_SVC="wikicurate-watcher.service"
    RESCAN_SVC="wikicurate-rescan.service"
    RESCAN_TIMER="wikicurate-rescan.timer"
fi
```

**register (Linux)**:
```bash
mkdir -p "$SYSTEMD_DIR"

# wikicurate-watcher.service
cat > "$SYSTEMD_DIR/$WATCHER_SVC" << EOF
[Unit]
Description=WikiCurate Ingest Watcher
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash ${WATCHER}
WorkingDirectory=${SCRIPT_DIR}
Environment=PATH=${INJECTED_PATH}
Restart=always
RestartSec=5
StandardOutput=append:/tmp/wikicurate-watcher.log
StandardError=append:/tmp/wikicurate-watcher.log

[Install]
WantedBy=default.target
EOF

# wikicurate-rescan.service + .timer
cat > "$SYSTEMD_DIR/$RESCAN_SVC" << EOF
[Unit]
Description=WikiCurate Daily Rescan
[Service]
Type=oneshot
ExecStart=/bin/bash ${RESCAN_SCRIPT}
WorkingDirectory=${SCRIPT_DIR}
Environment=PATH=${INJECTED_PATH}
StandardOutput=append:/tmp/wikicurate-rescan.log
StandardError=append:/tmp/wikicurate-rescan.log
EOF

cat > "$SYSTEMD_DIR/$RESCAN_TIMER" << EOF
[Unit]
Description=WikiCurate Daily Rescan Timer
[Timer]
OnCalendar=*-*-* 07,10,13,16,19,21:00:00
Persistent=true
[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now "$WATCHER_SVC"
systemctl --user enable --now "$RESCAN_TIMER"
echo "✓ ingest-watcher 등록 완료"
echo "✓ daily-rescan 등록 완료 (07/10/13/16/19/21시)"
echo "  로그: tail -f /tmp/wikicurate-watcher.log"
```

**unregister (Linux)**:
```bash
systemctl --user stop  "$WATCHER_SVC"  2>/dev/null || true
systemctl --user disable "$WATCHER_SVC" 2>/dev/null || true
systemctl --user stop  "$RESCAN_TIMER" 2>/dev/null || true
systemctl --user disable "$RESCAN_TIMER" 2>/dev/null || true
rm -f "$SYSTEMD_DIR/$WATCHER_SVC" "$SYSTEMD_DIR/$RESCAN_SVC" "$SYSTEMD_DIR/$RESCAN_TIMER"
systemctl --user daemon-reload
```

**status (Linux)**:
```bash
if systemctl --user is-active "$WATCHER_SVC" > /dev/null 2>&1; then
    pid=$(systemctl --user show "$WATCHER_SVC" --property=MainPID --value)
    echo "● ingest-watcher: 실행 중 (PID $pid)"
else
    echo "○ ingest-watcher: 미등록"
fi
if systemctl --user is-active "$RESCAN_TIMER" > /dev/null 2>&1; then
    echo "● daily-rescan: 등록됨 (07/10/13/16/19/21시)"
else
    echo "○ daily-rescan: 미등록"
fi
```

**의존성 체크 메시지 (register 진입부)**:
```bash
# Before
echo "ERROR: yq 미설치. 'brew install yq' 후 재시도하세요."
# After
echo "ERROR: yq 미설치. '$(pkg_install_hint yq)' 후 재시도하세요."
```

**PATH 주입 (register 진입부, Linux 추가)**:
```bash
# fswatch → inotifywait
for bin in inotifywait codex claude gemini sqlite3 yq graphify; do
```

---

### 2. `scripts/watch-ingest.sh`

#### 의존성 체크

```bash
# Before
if ! command -v fswatch > /dev/null 2>&1; then
    echo "ERROR: fswatch 미설치. 'brew install fswatch' 후 재시도하세요."
    exit 1
fi

# After
if [ "$OS" = "Darwin" ]; then
    if ! command -v fswatch > /dev/null 2>&1; then
        echo "ERROR: fswatch 미설치. '$(pkg_install_hint fswatch)' 후 재시도하세요." >&2; exit 1
    fi
else
    if ! command -v inotifywait > /dev/null 2>&1; then
        echo "ERROR: inotifywait 미설치. '$(pkg_install_hint inotify-tools)' 후 재시도하세요." >&2; exit 1
    fi
fi
```

#### md5 → md5_short 함수 교체

```bash
# Before (5곳: 185, 194, 214, 256, 270)
h=$(echo "$root" | md5 | cut -c1-8)

# After
h=$(md5_short "$root")
```

#### fswatch → inotifywait 분기

```bash
# Before
fswatch \
    --event Created --event Updated --event MovedTo \
    --latency 1 \
    --exclude '.*\.DS_Store$' --exclude '.*\.swp$' --exclude '.*~$' --exclude '.*/error/.*' \
    "$inbox_dir" >> "/tmp/wikicurate-${h}.queue" &

# After
if [ "$OS" = "Darwin" ]; then
    fswatch \
        --event Created --event Updated --event MovedTo \
        --latency 1 \
        --exclude '.*\.DS_Store$' --exclude '.*\.swp$' --exclude '.*~$' --exclude '.*/error/.*' \
        "$inbox_dir" >> "/tmp/wikicurate-${h}.queue" &
else
    inotifywait -m -r \
        -e create -e moved_to \
        --exclude '(\.DS_Store|\.swp|~|/error/)' \
        --format '%w%f' \
        "$inbox_dir" >> "/tmp/wikicurate-${h}.queue" &
fi
```

> **설계 근거**: queue 파일은 "변경 발생" 신호로만 사용됨. 실제 파일 처리는 `find "$inbox_dir"`로 직접 스캔하므로 inotifywait 출력 포맷 차이가 로직에 영향 없음.

#### yq 설치 안내

```bash
# Before
echo "ERROR: yq 미설치. 'brew install yq' 후 재시도하세요."
# After
echo "ERROR: yq 미설치. '$(pkg_install_hint yq)' 후 재시도하세요."
```

---

### 3. `scripts/daily-rescan.sh`

```bash
# Before (line 14)
echo "ERROR: yq 미설치. 'brew install yq' 후 재시도하세요."
# After
echo "ERROR: yq 미설치. '$(pkg_install_hint yq)' 후 재시도하세요."
```

---

### 4. `deploy.sh`

```bash
# Before (line 16)
echo "ERROR: yq 미설치. 'brew install yq' 후 재시도하세요."
# After
echo "ERROR: yq 미설치. '$(pkg_install_hint yq)' 후 재시도하세요."
```

---

## 대상 파일 및 변경 성격 요약

| 파일 | 변경 성격 | 변경 규모 |
|------|-----------|-----------|
| `scripts/watcher.sh` | 수정 | 대 (Linux 분기 전체 추가) |
| `scripts/watch-ingest.sh` | 수정 | 중 (fswatch 분기 + md5 함수화) |
| `scripts/daily-rescan.sh` | 수정 | 소 (메시지 1줄) |
| `deploy.sh` | 수정 | 소 (메시지 1줄) |

---

## 연계 정합성 검토

- `_system/` 파일 변경 없음
- `wikicurate.yaml` 변경 없음
- macOS 기존 동작 경로는 `if [ "$OS" = "Darwin" ]` 블록으로 완전히 보존

---

## `install.sh` 추가 (범위 확장)

### 역할

`./install.sh` 한 번 실행으로 전체 초기 설치 완료.

```
1. 시스템 의존성 설치 (OS별)
2. graphify 설치 (npm)
3. AI 에이전트 확인 (설치 안내)
4. deploy.sh --setup 자동 실행 (wikicurate.yaml 생성)
5. deploy.sh 자동 실행 (배포)
```

### OS별 의존성 설치

| 패키지 | macOS | Linux |
|--------|-------|-------|
| `yq` | `brew install yq` | snap 또는 GitHub 바이너리 (amd64/arm64) |
| 파일 감시 | `brew install fswatch` | `apt-get install inotify-tools` |
| `sqlite3` | `brew install sqlite3` | `apt-get install sqlite3` |
| `python3` | 기본 설치됨 | `apt-get install python3` |

### 동작 규칙

- 이미 설치된 패키지는 건너뜀 (idempotent)
- AI 에이전트(claude/codex/gemini) 없으면 경고만 출력, 중단하지 않음
- `wikicurate.yaml`이 이미 있으면 setup 마법사 건너뜀 (재실행 안전)

---

## 미결 사항

- Linux에서 로그인 없이 systemd user service를 유지하려면 `loginctl enable-linger $USER` 필요. deploy.sh 또는 watcher.sh register 시 안내 메시지만 출력하고 자동 실행은 하지 않음 (root 권한 불필요).
