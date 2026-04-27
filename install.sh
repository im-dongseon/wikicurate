#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS=$(uname -s)

# ── 출력 헬퍼 ─────────────────────────────────────────────────────────────
ok()   { echo "  ✓ $*"; }
info() { echo "  → $*"; }
warn() { echo "  ⚠ $*"; }

# ── macOS 의존성 ───────────────────────────────────────────────────────────
install_deps_macos() {
    if ! command -v brew > /dev/null 2>&1; then
        echo "ERROR: Homebrew 미설치. https://brew.sh 에서 설치 후 재시도하세요." >&2
        exit 1
    fi

    for pkg in yq fswatch sqlite3; do
        if command -v "$pkg" > /dev/null 2>&1; then
            ok "$pkg (이미 설치됨)"
        else
            info "$pkg 설치 중..."
            brew install "$pkg"
            ok "$pkg 설치 완료"
        fi
    done
}

# ── Linux 의존성 ───────────────────────────────────────────────────────────
install_deps_linux() {
    sudo apt-get update -qq

    for pkg in sqlite3 inotify-tools python3; do
        if dpkg -l "$pkg" > /dev/null 2>&1; then
            ok "$pkg (이미 설치됨)"
        else
            info "$pkg 설치 중..."
            sudo apt-get install -y "$pkg"
            ok "$pkg 설치 완료"
        fi
    done

    # yq: snap 우선, 없으면 GitHub 바이너리
    if command -v yq > /dev/null 2>&1; then
        ok "yq (이미 설치됨)"
    elif command -v snap > /dev/null 2>&1; then
        info "yq 설치 중 (snap)..."
        sudo snap install yq
        ok "yq 설치 완료"
    else
        info "yq 설치 중 (GitHub 바이너리)..."
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64)  YQ_ARCH="amd64" ;;
            aarch64) YQ_ARCH="arm64" ;;
            *)
                echo "ERROR: 지원하지 않는 아키텍처: $ARCH" >&2
                exit 1
                ;;
        esac
        sudo wget -qO /usr/local/bin/yq \
            "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${YQ_ARCH}"
        sudo chmod +x /usr/local/bin/yq
        ok "yq 설치 완료"
    fi
}

# ── graphify ───────────────────────────────────────────────────────────────
check_graphify() {
    if command -v graphify > /dev/null 2>&1; then
        ok "graphify (이미 설치됨)"
    elif command -v npm > /dev/null 2>&1; then
        info "graphify 설치 중..."
        npm install -g graphify
        ok "graphify 설치 완료"
    else
        warn "graphify 미설치 — Node.js/npm이 없어 자동 설치 불가"
        warn "Node.js 설치 후 'npm install -g graphify' 실행 필요"
    fi
}

# ── AI 에이전트 확인 ───────────────────────────────────────────────────────
check_ai_agents() {
    local found=false
    for agent in claude codex gemini; do
        if command -v "$agent" > /dev/null 2>&1; then
            ok "$agent (사용 가능)"
            found=true
        fi
    done
    if [ "$found" = false ]; then
        echo ""
        warn "AI 에이전트가 없습니다. 최소 1개 필요합니다:"
        warn "  Claude Code: https://docs.anthropic.com/en/docs/agents-and-tools/claude-code"
        warn "  Codex CLI:   https://developers.openai.com/codex/cli"
        warn "  Gemini CLI:  https://github.com/google/gemini-cli"
        echo ""
        read -r -p "에이전트 설치 후 계속하려면 Enter를 누르세요..."
    fi
}

# ── 메인 ──────────────────────────────────────────────────────────────────
echo "========================================"
echo "  WikiCurate 설치"
echo "========================================"
echo ""

echo "[1/3] 시스템 의존성 설치"
if [ "$OS" = "Darwin" ]; then
    install_deps_macos
else
    install_deps_linux
fi
check_graphify
check_ai_agents
echo ""

echo "[2/3] 위키 경로 설정"
CONFIG="$SCRIPT_DIR/wikicurate.yaml"
if [ -f "$CONFIG" ]; then
    ok "wikicurate.yaml 이미 존재 — setup 건너뜀"
    echo "     (재설정하려면 './deploy.sh --setup' 실행)"
else
    "$SCRIPT_DIR/deploy.sh" --setup
fi
echo ""

echo "[3/3] 시스템 배포"
"$SCRIPT_DIR/deploy.sh"
echo ""

echo "========================================"
echo "  설치 완료"
echo "========================================"
echo ""
echo "다음 단계: 위키 디렉토리에서 AI 에이전트를 열고 /setup 을 실행하세요."
echo ""
