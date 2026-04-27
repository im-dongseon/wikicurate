#!/usr/bin/env bash

# WikiCurate Deployment Script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS=$(uname -s)

pkg_install_hint() {
    local pkg="$1"
    if [ "$OS" = "Darwin" ]; then
        echo "brew install $pkg"
    else
        echo "sudo apt-get install -y $pkg"
    fi
}

# 버전 로드
if [ ! -f "$SCRIPT_DIR/_system/VERSION" ]; then
  echo "Error: _system/VERSION not found." >&2
  exit 1
fi
VERSION="$(cat "$SCRIPT_DIR/_system/VERSION" | tr -d '[:space:]')"

# yq 의존성 체크
if ! command -v yq > /dev/null 2>&1; then
  echo "ERROR: yq 미설치. '$(pkg_install_hint yq)' 후 재시도하세요." >&2
  exit 1
fi

# 옵션 파싱 — config 로딩보다 먼저 수행해야 --setup 플래그를 올바르게 인식
# (./deploy.sh --dry-run --setup 처럼 순서가 바뀌어도 마법사가 실행되도록)
DRY_RUN=false
SETUP=false
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=true ;;
    --setup) SETUP=true ;;
    *) echo "Unknown option: $arg" >&2; echo "Usage: $0 [--dry-run|-n] [--setup]" >&2; exit 1 ;;
  esac
done

# ── 인터랙티브 마법사 ────────────────────────────────────────────────────
run_setup_wizard() {
  local config_path="$1"
  echo "=== WikiCurate 초기 설정 ==="

  # 마이그레이션: 기존 .env가 있으면 DEPLOY_PATHS를 기본값으로 로드
  local existing_paths=()
  local env_file
  env_file="$(dirname "$config_path")/.env"
  if [ -f "$env_file" ]; then
    echo "기존 .env 발견 — DEPLOY_PATHS를 기본값으로 불러옵니다."
    # shellcheck source=/dev/null
    source "$env_file"
    existing_paths=("${DEPLOY_PATHS[@]:-}")
  fi

  echo "배포 경로를 입력하세요. (빈 줄로 종료)"
  echo ""

  local wikis_yaml=""
  local idx=1
  while true; do
    local default_path="${existing_paths[$((idx-1))]:-}"
    if [ -n "$default_path" ]; then
      printf "경로 %d (기본값: %s): " "$idx" "$default_path"
    else
      printf "경로 %d (Enter로 종료): " "$idx"
    fi
    read -r deploy_path
    deploy_path="${deploy_path:-$default_path}"
    [ -z "$deploy_path" ] && break

    # 유효성 검사: 경로 존재 여부
    if [ ! -d "$deploy_path" ]; then
      echo "  경고: 디렉토리가 존재하지 않습니다 — $deploy_path"
      printf "  그래도 추가하시겠습니까? [y/N]: "
      read -r confirm
      [[ "$confirm" =~ ^[Yy]$ ]] || continue
    fi

    printf "  wiki-inbox 경로 (기본값: %s/wiki-inbox, Enter로 기본값 사용): " "$deploy_path"
    read -r inbox_path

    # YAML 안전성: 경로에 #, : 등 의미 문자가 포함될 수 있으므로 따옴표로 감싼다
    if [ -z "$inbox_path" ]; then
      wikis_yaml+="  - deploy: \"$deploy_path\""$'\n'
    else
      wikis_yaml+="  - deploy: \"$deploy_path\""$'\n'
      wikis_yaml+="    wiki-inbox: \"$inbox_path\""$'\n'
    fi
    idx=$((idx + 1))
  done

  printf "에이전트 (codex/claude/gemini, 기본값: codex): "
  read -r agent
  agent="${agent:-codex}"
  printf "감시 주기 초 (기본값: 600): "
  read -r interval
  interval="${interval:-600}"

  cat > "$config_path" <<EOF
wikis:
${wikis_yaml}
agent: $agent
interval: $interval
EOF

  echo ""
  echo "wikicurate.yaml 저장 완료: $config_path"
  if [ -f "$env_file" ]; then
    rm "$env_file"
    echo "기존 .env 자동 삭제 완료: $env_file"
  fi
  echo ""
}

# ── 설정 로드 ────────────────────────────────────────────────────────────
CONFIG="$SCRIPT_DIR/wikicurate.yaml"

# wikicurate.yaml 없거나 --setup 플래그가 있으면 인터랙티브 마법사 실행
if [ ! -f "$CONFIG" ] || [ "$SETUP" = "true" ]; then
  run_setup_wizard "$CONFIG"
fi

# yaml에서 deploy path 목록 읽기 (bash 3 호환)
DEPLOY_PATHS=()
while IFS= read -r p; do
  DEPLOY_PATHS+=("$p")
done < <(yq '.wikis[].deploy' "$CONFIG")

if [ "${#DEPLOY_PATHS[@]}" -eq 0 ]; then
  echo "Error: wikicurate.yaml에 wikis 경로가 설정되지 않았습니다." >&2
  exit 1
fi

if [ "$DRY_RUN" = true ]; then
  echo "[DRY-RUN] 실제 변경 없이 검토만 수행합니다."
  echo ""
fi

# dry-run 헬퍼: 실제 실행 또는 출력
run() {
  if [ "$DRY_RUN" = true ]; then
    echo "  [would run] $*"
  else
    "$@"
  fi
}

deploy_to() {
  local TARGET="$1"
  echo ">>> Deploying WikiCurate v${VERSION} to $TARGET..."

  # 1. _system 배포 (wiki-schema.md + commands/ 포함)
  echo "1. _system/ 동기화"
  if [ "$DRY_RUN" = true ]; then
    \rsync -av --delete --dry-run "$SCRIPT_DIR/_system/" "$TARGET/_system/"
  else
    \rsync -av --delete "$SCRIPT_DIR/_system/" "$TARGET/_system/"
  fi
  echo ""

  # 2. 루트 에이전트 지침 생성
  echo "2. 루트 에이전트 지침 생성"
  # CLAUDE.md — symlink 유지 (Claude Code는 ~/.claude/skills/ + PreToolUse 훅으로 graphify 처리)
  run \ln -sf _system/wiki-schema.md "$TARGET/CLAUDE.md"

  # 헬퍼: wiki-schema 복사 + graphify always-on 섹션 추가
  append_graphify_section() {
    local target_file="$1"
    cat >> "$target_file" << 'GRAPHIFY_SECTION'

---

## graphify (always-on)

`graphify-out/GRAPH_REPORT.md`가 존재하면 아키텍처·코드베이스 질문에 답하기 전에 먼저 읽는다.
이 파일은 god nodes, community 구조, surprising connections의 1-page 요약이다.
존재하지 않으면 이 규칙을 무시하고 위의 지식 그래프 절차를 따른다.
GRAPHIFY_SECTION
  }

  # AGENTS.md — 실제 파일: wiki-schema 복사 + graphify always-on 섹션 (Codex 대상)
  if [ "$DRY_RUN" = true ]; then
    echo "  [would run] rm symlink + cp wiki-schema.md + graphify section → $TARGET/AGENTS.md"
  else
    rm -f "$TARGET/AGENTS.md"
    cp "$SCRIPT_DIR/_system/wiki-schema.md" "$TARGET/AGENTS.md"
    append_graphify_section "$TARGET/AGENTS.md"
  fi

  # GEMINI.md — 실제 파일: wiki-schema 복사 + graphify always-on 섹션 (Gemini CLI 대상)
  if [ "$DRY_RUN" = true ]; then
    echo "  [would run] rm symlink + cp wiki-schema.md + graphify section → $TARGET/GEMINI.md"
  else
    rm -f "$TARGET/GEMINI.md"
    cp "$SCRIPT_DIR/_system/wiki-schema.md" "$TARGET/GEMINI.md"
    append_graphify_section "$TARGET/GEMINI.md"
  fi
  echo ""

  # 3. Claude Code 슬래시 커맨드 심볼릭 링크 생성
  echo "3. .claude/commands 심볼릭 링크 생성"
  run \mkdir -p "$TARGET/.claude"
  run \ln -sf ../_system/commands "$TARGET/.claude/commands"
  echo ""

  # 4. Claude Code 권한 설정 배포
  echo "4. .claude/settings.json 배포"
  run \cp "$SCRIPT_DIR/.claude/settings.json" "$TARGET/.claude/settings.json"
  echo ""

  # 5. wiki-inbox/ 생성 (env()로 특수문자 경로 안전 처리)
  echo "5. wiki-inbox/ 생성"
  inbox_dir=$(TARGET="$TARGET" yq \
      '.wikis[] | select(.deploy == env(TARGET)) | .["wiki-inbox"] // (env(TARGET) + "/wiki-inbox")' \
      "$CONFIG")
  run \mkdir -p "$inbox_dir"
  run \mkdir -p "$inbox_dir/error"
  echo ""

  # 6. .wikicurate 생성/갱신 (inbox 오버라이드가 있는 경우에만)
  echo "6. .wikicurate 갱신"
  WIKICURATE_TARGET="$TARGET" WIKICURATE_INBOX="$inbox_dir" WIKICURATE_DRY_RUN="$DRY_RUN" python3 - <<'PYEOF'
import json, os
target   = os.environ["WIKICURATE_TARGET"]
inbox    = os.environ["WIKICURATE_INBOX"]
dry_run  = os.environ.get("WIKICURATE_DRY_RUN", "false") == "true"
default  = os.path.join(target, "wiki-inbox")
cfg_path = os.path.join(target, ".wikicurate")

if inbox == default:
    print("  inbox가 기본 경로 — .wikicurate 변경 없음")
else:
    cfg = {}
    try:
        with open(cfg_path) as f:
            cfg = json.load(f)
    except Exception:
        pass
    cfg["inbox_path"] = inbox
    if dry_run:
        print(f"  [would write] .wikicurate: inbox_path = {inbox}")
    else:
        with open(cfg_path, "w") as f:
            json.dump(cfg, f, ensure_ascii=False, indent=2)
        print(f"  .wikicurate 갱신: inbox_path = {inbox}")
PYEOF
  echo ""

  # 7. .codex/hooks.json 생성 (Codex PreToolUse 훅)
  echo "7. .codex/hooks.json 생성 (Codex PreToolUse 훅)"
  if [ "$DRY_RUN" = true ]; then
    echo "  [would run] create $TARGET/.codex/hooks.json"
  else
    mkdir -p "$TARGET/.codex"
    cat > "$TARGET/.codex/hooks.json" << 'CODEX_HOOKS'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "[ -f graphify-out/GRAPH_REPORT.md ] && echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"graphify: Knowledge graph exists. Read graphify-out/GRAPH_REPORT.md for god nodes and community structure before searching raw files.\"}}' || true"
          }
        ]
      }
    ]
  }
}
CODEX_HOOKS
  fi
  echo ""

  # 8. .gemini/settings.json 생성 (Gemini CLI BeforeTool 훅)
  echo "8. .gemini/settings.json 생성 (Gemini CLI BeforeTool 훅)"
  if [ "$DRY_RUN" = true ]; then
    echo "  [would run] create $TARGET/.gemini/settings.json"
  else
    mkdir -p "$TARGET/.gemini"
    cat > "$TARGET/.gemini/settings.json" << 'GEMINI_SETTINGS'
{
  "hooks": {
    "BeforeTool": [
      {
        "matcher": "read_file|list_directory",
        "hooks": [
          {
            "type": "command",
            "command": "[ -f graphify-out/GRAPH_REPORT.md ] && echo '{\"decision\":\"allow\",\"additionalContext\":\"graphify: Knowledge graph exists. Read graphify-out/GRAPH_REPORT.md for god nodes and community structure before searching raw files.\"}' || echo '{\"decision\":\"allow\"}'"
          }
        ]
      }
    ]
  }
}
GEMINI_SETTINGS
  fi
  echo ""

  # 9. .github/copilot-instructions.md 생성 (GitHub Copilot Chat 대상)
  echo "9. .github/copilot-instructions.md 생성 (GitHub Copilot Chat 대상)"
  if [ "$DRY_RUN" = true ]; then
    echo "  [would run] create $TARGET/.github/copilot-instructions.md"
  else
    mkdir -p "$TARGET/.github"
    cat > "$TARGET/.github/copilot-instructions.md" << 'COPILOT_INSTRUCTIONS'
## graphify (always-on)

`graphify-out/GRAPH_REPORT.md`가 존재하면 아키텍처·코드베이스 질문에 답하기 전에 먼저 읽는다.
이 파일은 god nodes, community 구조, surprising connections의 1-page 요약이다.
존재하지 않으면 이 규칙을 무시한다.
COPILOT_INSTRUCTIONS
  fi
  echo ""

  echo ">>> Deployment to $TARGET completed."
  echo "    [참고] Copilot CLI 전역 통합은 수동 1회 실행 필요: graphify copilot install"
  echo ""
}

for DEPLOY_PATH in "${DEPLOY_PATHS[@]}"; do
  deploy_to "$DEPLOY_PATH"
  echo "----------------------------------------"
done

if [ "$DRY_RUN" = true ]; then
  echo "[DRY-RUN] 완료. 실제 배포하려면 --dry-run 없이 실행하세요."
else
  echo "========================================"
  echo "ingest-watcher 등록 중..."
  "$SCRIPT_DIR/scripts/watcher.sh" register
  echo ""
  echo "Done."
  echo ""
  echo "다음 단계: 각 배포 디렉토리에서 AI 에이전트를 열고 아래 커맨드를 실행하세요."
  echo ""
  echo "  /setup"
  echo ""
  echo "  → 환경 검증 및 초기 설정이 수행됩니다."
fi
