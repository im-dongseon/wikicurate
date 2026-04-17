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
AGENT="${WIKICURATE_AGENT:-codex}"
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

if ! command -v sqlite3 > /dev/null 2>&1; then
    echo "ERROR: sqlite3 미설치. 'brew install sqlite3' 후 재시도하세요." >&2
    exit 1
fi

# ── 에이전트 선택 (지정 에이전트 → codex → claude → gemini 순 fallback) ──
select_agent_cmd() {
    local candidates=("$1" codex claude gemini)
    local seen=()
    for agent in "${candidates[@]}"; do
        [[ ${#seen[@]} -gt 0 ]] && [[ " ${seen[*]} " == *" $agent "* ]] && continue
        seen+=("$agent")
        case "$agent" in
            codex)
                command -v codex > /dev/null 2>&1 && \
                    echo "codex -a never exec -s workspace-write --skip-git-repo-check" && return 0 ;;
            claude)
                command -v claude > /dev/null 2>&1 && \
                    echo "claude --dangerously-skip-permissions -p" && return 0 ;;
            gemini)
                command -v gemini > /dev/null 2>&1 && \
                    echo "gemini --yolo -p" && return 0 ;;
        esac
    done
    echo "ERROR: 사용 가능한 에이전트(codex/claude/gemini)가 없습니다." >&2
    return 1
}

AGENT_CMD=$(select_agent_cmd "$AGENT") || exit 1

build_agent_prompt() {
    local action="$1"
    local file="${2:-}"
    local selected_agent="${AGENT_CMD%% *}"

    case "$selected_agent" in
        codex)
            case "$action" in
                ingest)
                    printf "Read the playbook at _system/commands/ingest.md and execute it for this specific file only: %s." "$file"
                    ;;
                lint)
                    printf "Read the playbook at _system/commands/lint.md and execute it for the current vault."
                    ;;
            esac
            ;;
        *)
            case "$action" in
                ingest) printf "/ingest %s" "$file" ;;
                lint) printf "/lint" ;;
            esac
            ;;
    esac
}

# ── DB 헬퍼 함수 ──────────────────────────────────────────────────────
# DB_PATH는 루프 내에서 루트별로 설정됨
DB_PATH=""

db_exec() {
    local sql="$1"
    local out err_file rc
    err_file=$(mktemp)
    out=$(sqlite3 "$DB_PATH" -cmd ".timeout 5000" "$sql" 2>"$err_file")
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "[DB ERROR] (rc=$rc) $(cat "$err_file")" >&2
    fi
    rm -f "$err_file"
    echo "$out"
    return $rc
}

db_init() {
    mkdir -p "$(dirname "$DB_PATH")"
    db_exec "PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS ingest_retries (
            filepath    TEXT PRIMARY KEY,
            retry_count INTEGER DEFAULT 0,
            last_error  TEXT,
            updated_at  DATETIME DEFAULT CURRENT_TIMESTAMP
        );" > /dev/null
}

db_list_retries() {
    db_exec "SELECT filepath FROM ingest_retries;"
}

db_get_retry_count() {
    local fp_esc="${1//\'/\'\'}"
    db_exec "SELECT retry_count FROM ingest_retries WHERE filepath='${fp_esc}';"
}

db_delete() {
    local fp_esc="${1//\'/\'\'}"
    db_exec "DELETE FROM ingest_retries WHERE filepath='${fp_esc}';" > /dev/null
}

db_upsert_failure() {
    local fp_esc="${1//\'/\'\'}"
    local err_flat
    err_flat=$(printf '%s' "$2" | tr '\n' ' ' | tr '\r' ' ')
    err_flat=$(printf '%s' "$err_flat" | sed 's/[[:space:]]\+/ /g')
    local err_esc="${err_flat//\'/\'\'}"
    db_exec "INSERT INTO ingest_retries (filepath, retry_count, last_error, updated_at)
        VALUES ('${fp_esc}', 0, '${err_esc}', CURRENT_TIMESTAMP)
        ON CONFLICT(filepath) DO UPDATE SET
            retry_count = retry_count + 1,
            last_error  = '${err_esc}',
            updated_at  = CURRENT_TIMESTAMP;" > /dev/null
}

isolate_file() {
    local file="$1" root="$2"
    local error_dir="$root/raw/error"
    mkdir -p "$error_dir"

    local base ts dest filename ext
    base=$(basename "$file")
    ts=$(date +%Y%m%d_%H%M%S)

    if [[ "$base" == *.* ]]; then
        ext="${base##*.}"
        filename="${base%.*}"
        dest="$error_dir/${filename}.${ts}.${ext}"
    else
        dest="$error_dir/${base}.${ts}"
    fi

    if ! mv "$file" "$dest"; then
        return 1
    fi
    db_delete "$file" || true
    echo "  [ISOLATED] raw/error/$(basename "$dest")"
}

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

# ── 루트별 fswatch 기동 및 DB 초기화 ──────────────────────────────────
echo "[$(date +%H:%M:%S)] 에이전트: $AGENT_CMD"
echo "[$(date +%H:%M:%S)] 실행 주기: ${INTERVAL}초"
echo ""

watched=0
for root in "${DEPLOY_PATHS[@]}"; do
    raw_dir="$root/raw"
    if [ ! -d "$raw_dir" ]; then
        echo "[$(date +%H:%M:%S)] [SKIP] raw/ 없음: $root"
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

    DB_PATH="$root/_state/data/wikicurate-retries.db"
    db_init

    echo "[$(date +%H:%M:%S)] [감시 시작] $raw_dir"
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
        DB_PATH="$root/_state/data/wikicurate-retries.db"

        # fswatch 큐 drain (원자적)
        fswatch_list=""
        if [ -f "$queue" ] && [ -s "$queue" ]; then
            mv "$queue" "${queue}.tmp"
            touch "$queue"
            fswatch_list=$(sort -u "${queue}.tmp")
            rm -f "${queue}.tmp"
        fi

        # DB 재시도 목록 조회 + 유령 레코드 청소 (메인 루프, 서브셸 진입 전)
        retry_list=""
        while IFS= read -r rfile; do
            [ -n "$rfile" ] || continue
            if [ -f "$rfile" ]; then
                retry_list="${retry_list:+$retry_list$'\n'}$rfile"
            else
                db_delete "$rfile" || true
            fi
        done <<< "$(db_list_retries 2>/dev/null || true)"

        # fswatch 목록 + 재시도 목록 병합
        changed=$(printf '%s\n%s\n' "$fswatch_list" "$retry_list" | sort -u | grep -v '^$' || true)

        # 처리할 파일이 없으면 skip
        [ -n "$changed" ] || continue

        # 이전 ingest 실행 중이면 다음 주기로 연기
        if [ -f "$lock" ]; then
            echo "[$(date +%H:%M:%S)] 실행 중 — 연기: $(basename "$root")"
            continue
        fi

        file_count=$(printf '%s\n' "$changed" | grep -c .)
        echo "[$(date +%H:%M:%S)] 변경 감지 (${file_count}개) → ingest 시작: $(basename "$root")"

        # 비동기 실행 (서브셸)
        (
            touch "$lock"
            trap 'rm -f "$lock"' EXIT

            ok=0; fail=0
            while IFS= read -r file; do
                [ -f "$file" ] || continue

                # 재시도 횟수 확인 → 로그 접두사 결정
                rc_val=$(db_get_retry_count "$file" 2>/dev/null || true)
                if [ -n "$rc_val" ] && [ "$rc_val" -ge 1 ] 2>/dev/null; then
                    echo "  [RETRY ${rc_val}/5] $(basename "$file")"
                fi

                tmpout=$(mktemp)
                ingest_prompt=$(build_agent_prompt ingest "$file")
                if (cd "$root" && $AGENT_CMD "$ingest_prompt" > "$tmpout" 2>&1); then
                    ok=$((ok + 1))
                    db_delete "$file" || true
                else
                    fail=$((fail + 1))
                    err_msg=$(cat "$tmpout")
                    db_upsert_failure "$file" "$err_msg" || true

                    new_rc=$(db_get_retry_count "$file" 2>/dev/null || true)
                    if [ -n "$new_rc" ] && [ "$new_rc" -ge 5 ] 2>/dev/null; then
                        isolate_file "$file" "$root" || {
                            echo "  [ISOLATE ERROR] mv 실패 — DB에서 제거: $(basename "$file")"
                            db_delete "$file" || true
                        }
                    else
                        echo "  [FAIL] $(basename "$file")"
                        sed 's/^/    /' "$tmpout"
                    fi
                fi
                rm -f "$tmpout"
            done <<< "$changed"

            echo "[$(date +%H:%M:%S)] 완료 ($(basename "$root")): 성공 ${ok}개, 실패 ${fail}개"

            # ingest 성공 건수 > 0일 때만 lint 실행
            if [ "$ok" -gt 0 ]; then
                echo "[$(date +%H:%M:%S)] lint 시작: $(basename "$root")"
                lint_out=$(mktemp)
                lint_prompt=$(build_agent_prompt lint)
                if (cd "$root" && $AGENT_CMD "$lint_prompt" > "$lint_out" 2>&1); then
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
