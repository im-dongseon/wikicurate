#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OS=$(uname -s)
WATCHER="$SCRIPT_DIR/scripts/watch-ingest.sh"
RESCAN_SCRIPT="$SCRIPT_DIR/scripts/daily-rescan.sh"

pkg_install_hint() {
    local pkg="$1"
    if [ "$OS" = "Darwin" ]; then
        echo "brew install $pkg"
    else
        echo "sudo apt-get install -y $pkg"
    fi
}

# macOS
PLIST_LABEL="com.wikicurate.ingest-watcher"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
RESCAN_LABEL="com.wikicurate.daily-rescan"
RESCAN_PLIST="$HOME/Library/LaunchAgents/${RESCAN_LABEL}.plist"

# Linux
SYSTEMD_DIR="$HOME/.config/systemd/user"
WATCHER_SVC="wikicurate-watcher.service"
RESCAN_SVC="wikicurate-rescan.service"
RESCAN_TIMER="wikicurate-rescan.timer"

case "${1:-}" in

register)
    # 의존성 확인
    if ! command -v yq > /dev/null 2>&1; then
        echo "ERROR: yq 미설치. '$(pkg_install_hint yq)' 후 재시도하세요." >&2
        exit 1
    fi
    if ! command -v sqlite3 > /dev/null 2>&1; then
        echo "ERROR: sqlite3 미설치. '$(pkg_install_hint sqlite3)' 후 재시도하세요." >&2
        exit 1
    fi
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

    # wikicurate.yaml 존재 확인
    CONFIG="$SCRIPT_DIR/wikicurate.yaml"
    if [ ! -f "$CONFIG" ]; then
        echo "ERROR: wikicurate.yaml 없음. './deploy.sh --setup' 을 먼저 실행하세요." >&2
        exit 1
    fi

    # 등록 시점에 실제 바이너리 위치를 찾아 PATH에 주입
    RESOLVED_DIRS=""
    if [ "$OS" = "Darwin" ]; then
        watcher_bins="fswatch codex claude gemini sqlite3 yq graphify"
    else
        watcher_bins="inotifywait codex claude gemini sqlite3 yq graphify"
    fi
    for bin in $watcher_bins; do
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

    if [ "$OS" = "Darwin" ]; then
        # ── macOS: launchd ──────────────────────────────────────────────
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

    else
        # ── Linux: systemd user service ─────────────────────────────────
        mkdir -p "$SYSTEMD_DIR"

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
        echo "  주입된 PATH: $INJECTED_PATH"
        echo "  로그: tail -f /tmp/wikicurate-watcher.log"
        echo "✓ daily-rescan 등록 완료 (07/10/13/16/19/21시)"
        echo "  로그: tail -f /tmp/wikicurate-rescan.log"
        echo ""
        echo "  [참고] 서버에서 로그아웃 후에도 watcher를 유지하려면:"
        echo "         loginctl enable-linger \$USER"
    fi
    ;;

unregister)
    if [ "$OS" = "Darwin" ]; then
        launchctl unload "$PLIST_PATH" 2>/dev/null || true
        rm -f "$PLIST_PATH"
        echo "✓ ingest-watcher 해제 완료"
        launchctl unload "$RESCAN_PLIST" 2>/dev/null || true
        rm -f "$RESCAN_PLIST"
        echo "✓ daily-rescan 해제 완료"
    else
        systemctl --user stop    "$WATCHER_SVC"  2>/dev/null || true
        systemctl --user disable "$WATCHER_SVC"  2>/dev/null || true
        systemctl --user stop    "$RESCAN_TIMER" 2>/dev/null || true
        systemctl --user disable "$RESCAN_TIMER" 2>/dev/null || true
        rm -f "$SYSTEMD_DIR/$WATCHER_SVC" "$SYSTEMD_DIR/$RESCAN_SVC" "$SYSTEMD_DIR/$RESCAN_TIMER"
        systemctl --user daemon-reload
        echo "✓ ingest-watcher 해제 완료"
        echo "✓ daily-rescan 해제 완료"
    fi
    ;;

status)
    if [ "$OS" = "Darwin" ]; then
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
    else
        # ingest-watcher
        if systemctl --user is-active "$WATCHER_SVC" > /dev/null 2>&1; then
            pid=$(systemctl --user show "$WATCHER_SVC" --property=MainPID --value)
            echo "● ingest-watcher: 실행 중 (PID $pid)"
        else
            echo "○ ingest-watcher: 미등록"
        fi
        # daily-rescan
        if systemctl --user is-active "$RESCAN_TIMER" > /dev/null 2>&1; then
            echo "● daily-rescan: 등록됨 (07/10/13/16/19/21시)"
        else
            echo "○ daily-rescan: 미등록"
        fi
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
