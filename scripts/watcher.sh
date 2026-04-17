#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST_LABEL="com.wikicurate.ingest-watcher"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
WATCHER="$SCRIPT_DIR/scripts/watch-ingest.sh"

case "${1:-}" in

register)
    # sqlite3 설치 여부 확인
    if ! command -v sqlite3 > /dev/null 2>&1; then
        echo "ERROR: sqlite3 미설치. 'brew install sqlite3' 후 재시도하세요." >&2
        exit 1
    fi

    # launchd는 제한된 PATH에서 실행됨
    # 등록 시점에 실제 바이너리 위치를 찾아 plist EnvironmentVariables에 주입
    RESOLVED_DIRS=""
    for bin in fswatch claude gemini sqlite3; do
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
    ;;

unregister)
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
    echo "✓ ingest-watcher 해제 완료"
    ;;

status)
    if launchctl list 2>/dev/null | grep -q "$PLIST_LABEL"; then
        echo "● 실행 중 ($PLIST_LABEL)"
        launchctl list "$PLIST_LABEL" 2>/dev/null || true
    else
        echo "○ 미등록 또는 중지 상태"
    fi
    ;;

log)
    tail -f /tmp/wikicurate-watcher.log
    ;;

*)
    echo "Usage: $0 {register|unregister|status|log}"
    exit 1
    ;;
esac
