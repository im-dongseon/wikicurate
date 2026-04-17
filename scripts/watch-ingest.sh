#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# .env 로드 (DEPLOY_PATHS 포함)
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo "ERROR: .env not found at $SCRIPT_DIR/.env" >&2
    exit 1
fi
source "$SCRIPT_DIR/.env"

# .env 로드 이후 선택적 환경변수 기본값 적용
AGENT="${WIKICURATE_AGENT:-claude}"
INTERVAL="${WIKICURATE_INTERVAL:-600}"

# ── 사전 검증 ──────────────────────────────────────────────────────────
if [ -z "${DEPLOY_PATHS[*]:-}" ]; then
    echo "ERROR: DEPLOY_PATHS is not set in .env" >&2
    exit 1
fi

if ! command -v fswatch > /dev/null 2>&1; then
    echo "ERROR: fswatch 미설치. 'brew install fswatch' 후 재시도하세요." >&2
    exit 1
fi

# ── 에이전트 선택 (지정 에이전트 → claude → gemini 순 fallback) ────────
select_agent_cmd() {
    local candidates=("$1" claude gemini)
    local seen=()
    for agent in "${candidates[@]}"; do
        [[ ${#seen[@]} -gt 0 ]] && [[ " ${seen[*]} " == *" $agent "* ]] && continue
        seen+=("$agent")
        case "$agent" in
            claude)
                command -v claude > /dev/null 2>&1 && \
                    echo "claude --dangerously-skip-permissions -p" && return 0 ;;
            gemini)
                command -v gemini > /dev/null 2>&1 && \
                    echo "gemini --yolo -p" && return 0 ;;
        esac
    done
    echo "ERROR: 사용 가능한 에이전트(claude/gemini)가 없습니다." >&2
    return 1
}

AGENT_CMD=$(select_agent_cmd "$AGENT") || exit 1

# ── 종료 시 정리 ───────────────────────────────────────────────────────
cleanup() {
    echo "[$(date +%H:%M:%S)] 종료 — 임시 파일 정리"
    for root in "${DEPLOY_PATHS[@]}"; do
        h=$(echo "$root" | md5 | cut -c1-8)
        rm -f "/tmp/wikicurate-${h}.queue" "/tmp/wikicurate-${h}.lock"
    done
    kill 0 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# ── 시작 시 스테일 lock 파일 정리 (이전 SIGKILL/비정상 종료 대비) ──────
for root in "${DEPLOY_PATHS[@]}"; do
    h=$(echo "$root" | md5 | cut -c1-8)
    rm -f "/tmp/wikicurate-${h}.lock"
done

# ── 루트별 fswatch 기동 ────────────────────────────────────────────────
echo "[$(date +%H:%M:%S)] 에이전트: $AGENT_CMD"
echo "[$(date +%H:%M:%S)] 실행 주기: ${INTERVAL}초"
echo ""

watched=0
for root in "${DEPLOY_PATHS[@]}"; do
    raw_dir="$root/raw"
    if [ ! -d "$raw_dir" ]; then
        echo "[SKIP] raw/ 없음: $root"
        continue
    fi
    h=$(echo "$root" | md5 | cut -c1-8)
    touch "/tmp/wikicurate-${h}.queue"
    fswatch \
        --event Created \
        --event Updated \
        --event MovedTo \
        --latency 1 \
        --exclude '.*\.DS_Store$' \
        --exclude '.*\.swp$' \
        --exclude '.*~$' \
        "$raw_dir" >> "/tmp/wikicurate-${h}.queue" &
    echo "[감시 시작] $raw_dir"
    watched=$((watched + 1))
done

if [ "$watched" -eq 0 ]; then
    echo "ERROR: 감시할 raw/ 디렉토리가 없습니다. DEPLOY_PATHS 내에 raw/를 생성하세요." >&2
    exit 1
fi

echo ""

# ── 공유 타이머 루프 ───────────────────────────────────────────────────
while true; do
    sleep "$INTERVAL"

    for root in "${DEPLOY_PATHS[@]}"; do
        h=$(echo "$root" | md5 | cut -c1-8)
        queue="/tmp/wikicurate-${h}.queue"
        lock="/tmp/wikicurate-${h}.lock"

        # 큐 파일이 없거나 비어있으면 skip
        [ -f "$queue" ] && [ -s "$queue" ] || continue

        # 이전 ingest 실행 중이면 다음 주기로 연기
        if [ -f "$lock" ]; then
            echo "[$(date +%H:%M:%S)] 실행 중 — 연기: $(basename "$root")"
            continue
        fi

        # 원자적 큐 drain: mv로 먼저 분리 후 처리 (fswatch 경쟁 조건 방지)
        mv "$queue" "${queue}.tmp"
        touch "$queue"
        changed=$(sort -u "${queue}.tmp")
        rm -f "${queue}.tmp"

        file_count=$(echo "$changed" | grep -c .)
        echo "[$(date +%H:%M:%S)] 변경 감지 (${file_count}개) → ingest 시작: $(basename "$root")"

        # 비동기 실행 (서브셸)
        (
            touch "$lock"
            trap 'rm -f "$lock"' EXIT

            ok=0; fail=0
            while IFS= read -r file; do
                [ -f "$file" ] || continue
                tmpout=$(mktemp)
                if (cd "$root" && $AGENT_CMD "/ingest $file" > "$tmpout" 2>&1); then
                    ok=$((ok + 1))
                else
                    fail=$((fail + 1))
                    echo "  [FAIL] $(basename "$file")"
                    sed 's/^/    /' "$tmpout"
                fi
                rm -f "$tmpout"
            done <<< "$changed"
            echo "[$(date +%H:%M:%S)] 완료 ($(basename "$root")): 성공 ${ok}개, 실패 ${fail}개"

            # ingest 성공 건수 > 0일 때만 lint 실행
            if [ "$ok" -gt 0 ]; then
                echo "[$(date +%H:%M:%S)] lint 시작: $(basename "$root")"
                lint_out=$(mktemp)
                if (cd "$root" && $AGENT_CMD "/lint" > "$lint_out" 2>&1); then
                    echo "[$(date +%H:%M:%S)] lint 완료: $(basename "$root")"
                else
                    echo "[$(date +%H:%M:%S)] lint 실패: $(basename "$root")"
                fi
                sed 's/^/    /' "$lint_out"
                rm -f "$lint_out"
            fi
        ) &
    done
done
