#!/usr/bin/env bash

# WikiCurate v0.1.0 Deployment Script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 옵션 파싱
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=true ;;
    *) echo "Unknown option: $arg" >&2; echo "Usage: $0 [--dry-run|-n]" >&2; exit 1 ;;
  esac
done

# .env 로드
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "Error: .env not found. Copy .env.example -> .env and set DEPLOY_PATHS." >&2
  exit 1
fi
source "$SCRIPT_DIR/.env"

if [ -z "${DEPLOY_PATHS[*]}" ]; then
  echo "Error: DEPLOY_PATHS is not set in .env" >&2
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
  echo ">>> Deploying WikiCurate v0.1.0 to $TARGET..."

  # 1. _system 배포 (wiki-schema.md + commands/ 포함)
  echo "1. _system/ 동기화"
  if [ "$DRY_RUN" = true ]; then
    \rsync -av --delete --dry-run "$SCRIPT_DIR/_system/" "$TARGET/_system/"
  else
    \rsync -av --delete "$SCRIPT_DIR/_system/" "$TARGET/_system/"
  fi
  echo ""

  # 2. 루트 에이전트 지침 심볼릭 링크 생성
  echo "2. 루트 에이전트 지침 심볼릭 링크 생성 (CLAUDE.md / AGENTS.md / GEMINI.md)"
  run \ln -sf _system/wiki-schema.md "$TARGET/CLAUDE.md"
  run \ln -sf _system/wiki-schema.md "$TARGET/AGENTS.md"
  run \ln -sf _system/wiki-schema.md "$TARGET/GEMINI.md"
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

  echo ">>> Deployment to $TARGET completed."
  echo ""
}

for DEPLOY_PATH in "${DEPLOY_PATHS[@]}"; do
  deploy_to "$DEPLOY_PATH"
  echo "----------------------------------------"
done

if [ "$DRY_RUN" = true ]; then
  echo "[DRY-RUN] 완료. 실제 배포하려면 --dry-run 없이 실행하세요."
else
  echo "Done."
  echo ""
  echo "다음 단계: 각 배포 디렉토리에서 AI 에이전트를 열고 아래 커맨드를 실행하세요."
  echo ""
  echo "  /setup"
  echo ""
  echo "  → 환경 검증 및 초기 설정이 수행됩니다."
fi
