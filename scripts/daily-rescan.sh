#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── 사전 검증 ────────────────────────────────────────────────────────────
CONFIG="$SCRIPT_DIR/wikicurate.yaml"
if [ ! -f "$CONFIG" ]; then
    echo "ERROR: wikicurate.yaml 없음. './deploy.sh --setup' 을 먼저 실행하세요." >&2
    exit 1
fi

if ! command -v yq > /dev/null 2>&1; then
    echo "ERROR: yq 미설치. 'brew install yq' 후 재시도하세요." >&2
    exit 1
fi

# wikicurate.yaml 파싱
DEPLOY_PATHS=()
while IFS= read -r p; do
    DEPLOY_PATHS+=("$p")
done < <(yq '.wikis[].deploy' "$CONFIG")

AGENT="${WIKICURATE_AGENT:-$(yq '.agent // "codex"' "$CONFIG")}"

if [ "${#DEPLOY_PATHS[@]}" -eq 0 ]; then
    echo "ERROR: wikicurate.yaml에 wikis 경로가 설정되지 않았습니다." >&2
    exit 1
fi

# ── 에이전트 선택 (watch-ingest.sh와 동일 로직) ────────────────────────
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
    echo "ERROR: 사용 가능한 에이전트가 없습니다." >&2; return 1
}

build_agent_prompt() {
    local action="$1" file="${2:-}"
    local selected_agent="${AGENT_CMD%% *}"
    case "$selected_agent" in
        codex)
            case "$action" in
                ingest)
                    if [ -n "$file" ]; then
                        printf "Read the playbook at _system/commands/ingest.md and execute it for this specific file only: %s." "$file"
                    else
                        printf "Read the playbook at _system/commands/ingest.md and execute it."
                    fi
                    ;;
                lint) printf "Read the playbook at _system/commands/lint.md and execute it for the current vault." ;;
                graphify) printf "Read the playbook at _system/commands/graphify.md and execute it." ;;
            esac ;;
        *)
            case "$action" in
                ingest)
                    if [ -n "$file" ]; then printf "/ingest %s" "$file"
                    else printf "/ingest"
                    fi
                    ;;
                lint) printf "/lint" ;;
                graphify) printf "/graphify" ;;
            esac ;;
    esac
}

AGENT_CMD=$(select_agent_cmd "$AGENT") || exit 1

VERSION="$(cat "$SCRIPT_DIR/_system/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "unknown")"
echo "[$(date +%H:%M:%S)] WikiCurate v${VERSION} — 일일 재스캔"
echo "[$(date +%H:%M:%S)] 에이전트: $AGENT_CMD"
echo ""

for root in "${DEPLOY_PATHS[@]}"; do
    raw_dir="$root/raw"
    if [ ! -d "$raw_dir" ]; then
        echo "[$(date +%H:%M:%S)] [SKIP] raw/ 없음: $root"
        continue
    fi

    # Pass 1: Google 스텁 재스캔
    ok=0; fail=0  # set -u 대비 — 스텁 없음 케이스에서도 lint 조건 평가에 사용됨
    stub_files=$(find "$raw_dir" -type f \( -name "*.gdoc" -o -name "*.gsheet" -o -name "*.gslides" \) 2>/dev/null || true)
    if [ -n "$stub_files" ]; then
        file_count=$(printf '%s\n' "$stub_files" | wc -l | tr -d ' ')
        echo "[$(date +%H:%M:%S)] [Pass 1] 재스캔 시작 (${file_count}개): $(basename "$root")"

        while IFS= read -r file; do
            tmpout=$(mktemp)
            ingest_prompt=$(build_agent_prompt ingest "$file")
            if (cd "$root" && $AGENT_CMD "$ingest_prompt" > "$tmpout" 2>&1); then
                ok=$((ok + 1))
                echo "  [OK] $(basename "$file")"
            else
                fail=$((fail + 1))
                echo "  [FAIL] $(basename "$file")"
                sed 's/^/    /' "$tmpout"
            fi
            rm -f "$tmpout"
        done <<< "$stub_files"

        echo "[$(date +%H:%M:%S)] [Pass 1] 완료 ($(basename "$root")): 성공 ${ok}개, 실패 ${fail}개"
    else
        echo "[$(date +%H:%M:%S)] [Pass 1] 스텁 파일 없음: $(basename "$root")"
    fi

    # Pass 2: raw/ 미처리 파일 회수 (모든 파일 타입, log.md에 없는 파일)
    # Google 스텁 유무와 무관하게 항상 실행 — pdf/docx 등 일반 파일 복구 포함
    # wiki-inbox/에 파일이 있으면 inbox 파일을 먼저 처리하고 raw/ fallback은 다음 실행으로 밀림 (의도된 동작)
    # watch-ingest.sh lock을 확인하지 않음 — 에이전트 호출은 직렬이므로 허용된 설계
    echo "[$(date +%H:%M:%S)] [Pass 2] raw/ 미처리 파일 스캔: $(basename "$root")"
    sweep_out=$(mktemp)
    sweep_prompt=$(build_agent_prompt ingest)
    pass2_ok=false
    if (cd "$root" && $AGENT_CMD "$sweep_prompt" > "$sweep_out" 2>&1); then
        echo "[$(date +%H:%M:%S)] [Pass 2] 완료: $(basename "$root")"
        pass2_ok=true
    else
        echo "[$(date +%H:%M:%S)] [Pass 2] 실패: $(basename "$root")"
    fi
    sed 's/^/    /' "$sweep_out"
    rm -f "$sweep_out"

    # lint + graphify: Pass 1(스텁 성공) 또는 Pass 2(raw/ 복구 성공) 중 하나라도 성공 시 실행
    if [ "$ok" -gt 0 ] || [ "$pass2_ok" = true ]; then
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
done

echo "[$(date +%H:%M:%S)] WikiCurate v${VERSION} — 일일 재스캔 완료"
