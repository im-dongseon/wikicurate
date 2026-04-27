#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OS=$(uname -s)

pkg_install_hint() {
    local pkg="$1"
    if [ "$OS" = "Darwin" ]; then
        echo "brew install $pkg"
    else
        echo "sudo apt-get install -y $pkg"
    fi
}

md5_short() {
    if [ "$OS" = "Darwin" ]; then
        echo "$1" | md5 | cut -c1-8
    else
        echo "$1" | md5sum | cut -c1-8
    fi
}

# ── 사전 검증 ──────────────────────────────────────────────────────────
# wikicurate.yaml 존재 확인
CONFIG="$SCRIPT_DIR/wikicurate.yaml"
if [ ! -f "$CONFIG" ]; then
    echo "ERROR: wikicurate.yaml 없음. './deploy.sh --setup' 을 먼저 실행하세요." >&2
    exit 1
fi

# yq 체크는 사용 전에 수행 (DEPLOY_PATHS 로딩이 yq를 호출하므로)
if ! command -v yq > /dev/null 2>&1; then
    echo "ERROR: yq 미설치. '$(pkg_install_hint yq)' 후 재시도하세요." >&2
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

if ! command -v sqlite3 > /dev/null 2>&1; then
    echo "ERROR: sqlite3 미설치. '$(pkg_install_hint sqlite3)' 후 재시도하세요." >&2
    exit 1
fi

# wikicurate.yaml 파싱 (의존성 검증 후)
DEPLOY_PATHS=()
while IFS= read -r p; do
    DEPLOY_PATHS+=("$p")
done < <(yq '.wikis[].deploy' "$CONFIG")

AGENT="${WIKICURATE_AGENT:-$(yq '.agent // "codex"' "$CONFIG")}"
INTERVAL="${WIKICURATE_INTERVAL:-$(yq '.interval // 600' "$CONFIG")}"

if [ "${#DEPLOY_PATHS[@]}" -eq 0 ]; then
    echo "ERROR: wikicurate.yaml에 wikis 경로가 설정되지 않았습니다." >&2
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
    local inbox_dir="${2:-}"   # 지역 변수: 호출부 build_agent_prompt ingest "$inbox_dir"
    local selected_agent="${AGENT_CMD%% *}"

    local root_dir="${3:-}"  # 세 번째 인자: root (codex 플레이북 절대경로용)

    case "$selected_agent" in
        codex)
            case "$action" in
                ingest)
                    # 플레이북 경로를 절대 경로로 지정 (workdir이 root가 아닐 수 있음)
                    printf "Read the playbook at %s/_system/commands/ingest.md and execute it for all files in %s." "$root_dir" "$inbox_dir"
                    ;;
                lint)
                    printf "Read the playbook at _system/commands/lint.md and execute it for the current vault."
                    ;;
                graphify)
                    printf "Read the playbook at _system/commands/graphify.md and execute it."
                    ;;
            esac
            ;;
        *)
            case "$action" in
                ingest) printf "/ingest %s" "$inbox_dir" ;;
                lint) printf "/lint" ;;
                graphify) printf "/graphify" ;;
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
    # 신규 설치(wiki-inbox 전환) 시 스테일 레코드(raw/ 경로 key) 정리
    db_exec "PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS ingest_retries (
            filepath    TEXT PRIMARY KEY,
            retry_count INTEGER DEFAULT 0,
            last_error  TEXT,
            updated_at  DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        DELETE FROM ingest_retries
          WHERE filepath NOT LIKE '%wiki-inbox%';" > /dev/null
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
    local file="$1" inbox_dir="$2"
    local error_dir="$inbox_dir/error"
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
    echo "  [ISOLATED] wiki-inbox/error/$(basename "$dest")"
}

# ── 종료 시 정리 ───────────────────────────────────────────────────────
cleanup() {
    echo "[$(date +%H:%M:%S)] 종료 — 임시 파일 정리"
    for root in "${DEPLOY_PATHS[@]}"; do
        h=$(md5_short "$root")
        rm -f "/tmp/wikicurate-${h}.queue" "/tmp/wikicurate-${h}.lock" "/tmp/wikicurate-${h}.inbox"
    done
    kill 0 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# ── 시작 시 스테일 lock 파일 정리 (이전 SIGKILL/비정상 종료 대비) ──────
for root in "${DEPLOY_PATHS[@]}"; do
    h=$(md5_short "$root")
    rm -f "/tmp/wikicurate-${h}.lock"
done

# ── 루트별 fswatch 기동 및 DB 초기화 ──────────────────────────────────
VERSION="$(cat "$SCRIPT_DIR/_system/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "unknown")"
echo "[$(date +%H:%M:%S)] WikiCurate v${VERSION}"
echo "[$(date +%H:%M:%S)] 에이전트: $AGENT_CMD"
echo "[$(date +%H:%M:%S)] 실행 주기: ${INTERVAL}초"
echo ""

watched=0
for root in "${DEPLOY_PATHS[@]}"; do
    # wiki-inbox 경로: yaml 오버라이드 또는 기본값 (env()로 특수문자 경로 안전 처리)
    inbox_dir=$(TARGET="$root" yq \
        '.wikis[] | select(.deploy == env(TARGET)) | .["wiki-inbox"] // (env(TARGET) + "/wiki-inbox")' \
        "$CONFIG")
    mkdir -p "$inbox_dir"
    mkdir -p "$inbox_dir/error"

    h=$(md5_short "$root")
    touch "/tmp/wikicurate-${h}.queue"
    # inbox_dir 경로를 저장 (타이머 루프에서 재참조)
    echo "$inbox_dir" > "/tmp/wikicurate-${h}.inbox"

    if [ "$OS" = "Darwin" ]; then
        fswatch \
            --event Created \
            --event Updated \
            --event MovedTo \
            --latency 1 \
            --exclude '.*\.DS_Store$' \
            --exclude '.*\.swp$' \
            --exclude '.*~$' \
            --exclude '.*/error/.*' \
            "$inbox_dir" >> "/tmp/wikicurate-${h}.queue" &
    else
        inotifywait -m -r \
            -e create -e moved_to \
            --exclude '(\.DS_Store|\.swp|~$|/error/)' \
            --format '%w%f' \
            "$inbox_dir" >> "/tmp/wikicurate-${h}.queue" &
    fi

    DB_PATH="$root/_state/data/wikicurate-retries.db"
    db_init

    echo "[$(date +%H:%M:%S)] [감시 시작] $inbox_dir"
    watched=$((watched + 1))
done

if [ "$watched" -eq 0 ]; then
    echo "ERROR: 감시할 wiki-inbox/ 디렉토리가 없습니다. wikicurate.yaml 경로를 확인하세요." >&2
    exit 1
fi

echo ""

# ── 네트워크 드라이브 마운트 대기 ─────────────────────────────────────
# Google Drive 공유 드라이브 등 네트워크 경로는 기동 직후 파일 목록이
# 아직 로드되지 않을 수 있으므로, 첫 스캔 전 짧게 대기한다.
STARTUP_DELAY="${WIKICURATE_STARTUP_DELAY:-30}"
if [ "$STARTUP_DELAY" -gt 0 ]; then
    echo "[$(date +%H:%M:%S)] 첫 스캔 대기 (${STARTUP_DELAY}초) — 네트워크 드라이브 마운트 대기 중..."
    sleep "$STARTUP_DELAY"
fi

# sleep 이후 다시 한 번 stale lock 정리
# (sleep 도중 이전 인스턴스의 async subshell이 lock을 재생성할 수 있음)
for root in "${DEPLOY_PATHS[@]}"; do
    h=$(md5_short "$root")
    rm -f "/tmp/wikicurate-${h}.lock"
done

# ── 공유 타이머 루프 ───────────────────────────────────────────────────
_FIRST_RUN=true
while true; do
    if $_FIRST_RUN; then
        _FIRST_RUN=false  # 시작 시 즉시 backlog 스캔 (sleep 건너뜀)
    else
        sleep "$INTERVAL"
    fi

    for root in "${DEPLOY_PATHS[@]}"; do
        h=$(md5_short "$root")
        queue="/tmp/wikicurate-${h}.queue"
        lock="/tmp/wikicurate-${h}.lock"
        inbox_file="/tmp/wikicurate-${h}.inbox"
        DB_PATH="$root/_state/data/wikicurate-retries.db"

        # inbox_dir 읽기 (기동 시 저장한 값)
        inbox_dir=""
        [ -f "$inbox_file" ] && inbox_dir=$(cat "$inbox_file")
        if [ -z "$inbox_dir" ]; then
            inbox_dir=$(TARGET="$root" yq \
                '.wikis[] | select(.deploy == env(TARGET)) | .["wiki-inbox"] // (env(TARGET) + "/wiki-inbox")' \
                "$CONFIG")
        fi

        # fswatch 큐 drain (신호 소비 — 실제 파일 목록은 wiki-inbox/ 직접 스캔)
        if [ -f "$queue" ] && [ -s "$queue" ]; then
            mv "$queue" "${queue}.tmp"
            touch "$queue"
            rm -f "${queue}.tmp"
        fi

        # wiki-inbox/ 직속 파일 수 확인 (트리거 조건: 새 파일 또는 이전 실패 잔류)
        # 숨김 파일(. 로 시작)은 ingest 대상 제외
        file_count=$(find "$inbox_dir" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | wc -l | tr -d ' ') || file_count=0
        [ "$file_count" -gt 0 ] || continue

        # 이전 ingest 실행 중이면 다음 주기로 연기
        if [ -f "$lock" ]; then
            echo "[$(date +%H:%M:%S)] 실행 중 — 연기: $(basename "$root")"
            continue
        fi

        echo "[$(date +%H:%M:%S)] 변경 감지 (${file_count}개) → ingest 시작: $(basename "$root")"

        # 비동기 실행 (서브셸)
        (
            touch "$lock"
            trap 'rm -f "$lock"' EXIT
            trap 'exit' TERM INT  # 부모 cleanup 상속 방지 — lock은 EXIT 트랩이 처리

            tmpout=$(mktemp)
            ingest_prompt=$(build_agent_prompt ingest "$inbox_dir" "$root")
            # inbox_dir이 root 밖에 있으면 공통 상위 디렉토리에서 실행
            # → workspace-write 샌드박스가 root와 inbox_dir을 모두 커버
            if [[ "$inbox_dir" == "$root/"* ]]; then
                work_dir="$root"
            else
                work_dir=$(dirname "$root")
            fi
            (cd "$work_dir" && $AGENT_CMD "$ingest_prompt" > "$tmpout" 2>&1) || true

            # post-check: wiki-inbox/ 잔류 파일 = 실패 파일
            fail=0
            while IFS= read -r file; do
                [ -n "$file" ] || continue
                fail=$((fail + 1))
                # 이전 재시도 횟수 표시 (upsert 전)
                rc_val=$(db_get_retry_count "$file" 2>/dev/null || true)
                if [ -n "$rc_val" ] && [ "$rc_val" -ge 1 ] 2>/dev/null; then
                    echo "  [RETRY ${rc_val}/5] $(basename "$file")"
                fi
                db_upsert_failure "$file" "$(cat "$tmpout")" || true
                # upsert 후 재시도 횟수 재확인 → 임계값 초과 시 격리
                rc_val=$(db_get_retry_count "$file" 2>/dev/null || true)
                if [ -n "$rc_val" ] && [ "$rc_val" -ge 5 ] 2>/dev/null; then
                    isolate_file "$file" "$inbox_dir" || {
                        echo "  [ISOLATE ERROR] mv 실패 — DB에서 제거: $(basename "$file")"
                        db_delete "$file" || true
                    }
                else
                    echo "  [FAIL] $(basename "$file")"
                    sed 's/^/    /' "$tmpout"
                fi
            done < <(find "$inbox_dir" -maxdepth 1 -type f ! -name '.*')

            # wiki-inbox/가 비었으면 전체 성공 → DB 클린업
            if [ -z "$(find "$inbox_dir" -maxdepth 1 -type f ! -name '.*' 2>/dev/null)" ]; then
                inbox_esc="${inbox_dir//\'/\'\'}"
                db_exec "DELETE FROM ingest_retries WHERE filepath LIKE '${inbox_esc}%';" > /dev/null || true
                echo "[$(date +%H:%M:%S)] 완료 ($(basename "$root")): 성공 ${file_count}개"
            else
                echo "[$(date +%H:%M:%S)] 완료 ($(basename "$root")): 실패 잔류 ${fail}개"
            fi

            # 잔류 파일 0개 (전체 성공)일 때만 lint 실행
            if [ "$fail" -eq 0 ]; then
                echo "[$(date +%H:%M:%S)] lint 시작: $(basename "$root")"
                lint_out=$(mktemp)
                lint_prompt=$(build_agent_prompt lint)
                if (cd "$root" && $AGENT_CMD "$lint_prompt" > "$lint_out" 2>&1); then
                    echo "[$(date +%H:%M:%S)] lint 완료: $(basename "$root")"
                    echo "[$(date +%H:%M:%S)] graphify 빌드 시작: $(basename "$root")"
                    graph_out=$(mktemp)
                    graphify_prompt=$(build_agent_prompt graphify)
                    if (cd "$root" && $AGENT_CMD "$graphify_prompt" > "$graph_out" 2>&1); then
                        echo "[$(date +%H:%M:%S)] graphify 빌드 완료: $(basename "$root")"
                    else
                        echo "[$(date +%H:%M:%S)] graphify 빌드 실패 (무시): $(basename "$root")"
                        sed 's/^/    /' "$graph_out"
                    fi
                    rm -f "$graph_out"
                else
                    echo "[$(date +%H:%M:%S)] lint 실패: $(basename "$root")"
                fi
                sed 's/^/    /' "$lint_out"
                rm -f "$lint_out"
            fi
            rm -f "$tmpout"
        ) &
    done
done
