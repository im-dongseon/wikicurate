#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST_LABEL="com.wikicurate.ingest-watcher"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
WATCHER="$SCRIPT_DIR/scripts/watch-ingest.sh"

RESCAN_LABEL="com.wikicurate.daily-rescan"
RESCAN_PLIST="$HOME/Library/LaunchAgents/${RESCAN_LABEL}.plist"
RESCAN_SCRIPT="$SCRIPT_DIR/scripts/daily-rescan.sh"

case "${1:-}" in

register)
    # 의존성 확인
    if ! command -v yq > /dev/null 2>&1; then
        echo "ERROR: yq 미설치. 'brew install yq' 후 재시도하세요." >&2
        exit 1
    fi
    if ! command -v sqlite3 > /dev/null 2>&1; then
        echo "ERROR: sqlite3 미설치. 'brew install sqlite3' 후 재시도하세요." >&2
        exit 1
    fi

    # wikicurate.yaml 존재 확인 (설정 파싱은 watch-ingest.sh에서 수행)
    CONFIG="$SCRIPT_DIR/wikicurate.yaml"
    if [ ! -f "$CONFIG" ]; then
        echo "ERROR: wikicurate.yaml 없음. './deploy.sh --setup' 을 먼저 실행하세요." >&2
        exit 1
    fi

    # launchd는 제한된 PATH에서 실행됨
    # 등록 시점에 실제 바이너리 위치를 찾아 plist EnvironmentVariables에 주입
    RESOLVED_DIRS=""
    for bin in fswatch codex claude gemini sqlite3 yq graphify; do
        bin_path=$(command -v "$bin" 2>/dev/null || true)
        if [ -n "$bin_path" ]; then
            bin_dir=$(dirname "$bin_path")
            case ":${RESOLVED_DIRS}:" in
                *":${bin_dir}:"*) ;;
                *) RESOLVED_DIRS="${RESOLVED_DIRS:+${RESOLVED_DIRS}:}${bin_dir}" ;;
            esac
        fi
    done
    INJECTED_PATH="${RESOLVED_DIRS:+${RESOLVED_DIRS}:}$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    # 이미 등록돼 있으면 먼저 해제 (idempotent)
    launchctl unload "$PLIST_PATH" 2>/dev/null || true

    mkdir -p "$HOME/Library/LaunchAgents"
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

    # daily-rescan plist 등록
    launchctl unload "$RESCAN_PLIST" 2>/dev/null || true
    cat > "$RESCAN_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${RESCAN_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${RESCAN_SCRIPT}</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>${INJECTED_PATH}</string>
    </dict>
    <key>WorkingDirectory</key>
    <string>${SCRIPT_DIR}</string>
    <key>StartCalendarInterval</key>
    <array>
        <dict><key>Hour</key><integer>7</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>10</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>13</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>16</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>19</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>21</integer><key>Minute</key><integer>0</integer></dict>
    </array>
    <key>StandardOutPath</key>
    <string>/tmp/wikicurate-rescan.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/wikicurate-rescan.log</string>
</dict>
</plist>
EOF
    launchctl load "$RESCAN_PLIST"
    echo "✓ daily-rescan 등록 완료 (07/10/13/16/19/21시)"
    echo "  로그: tail -f /tmp/wikicurate-rescan.log"
    ;;

unregister)
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
    echo "✓ ingest-watcher 해제 완료"
    launchctl unload "$RESCAN_PLIST" 2>/dev/null || true
    rm -f "$RESCAN_PLIST"
    echo "✓ daily-rescan 해제 완료"
    ;;

status)
    # ingest-watcher
    if launchctl list 2>/dev/null | grep -q "$PLIST_LABEL"; then
        pid=$(launchctl list "$PLIST_LABEL" 2>/dev/null | grep '"PID"' | awk -F'= ' '{print $2}' | tr -d ';')
        if [ -n "$pid" ]; then
            echo "● ingest-watcher: 실행 중 (PID $pid)"
        else
            echo "○ ingest-watcher: 등록됨 (중지 상태)"
        fi
    else
        echo "○ ingest-watcher: 미등록"
    fi
    # daily-rescan
    if launchctl list 2>/dev/null | grep -q "$RESCAN_LABEL"; then
        echo "● daily-rescan: 등록됨 (07/10/13/16/19/21시)"
    else
        echo "○ daily-rescan: 미등록"
    fi
    ;;

log)
    tail -f /tmp/wikicurate-watcher.log
    ;;

rescan-log)
    tail -f /tmp/wikicurate-rescan.log
    ;;

*)
    echo "Usage: $0 {register|unregister|status|log|rescan-log}"
    exit 1
    ;;
esac
