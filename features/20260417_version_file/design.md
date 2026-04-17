# Design: VERSION 파일 기반 버전 관리

- **Feature ID:** `20260417_version_file`
- **작업 시작일:** 2026-04-17
- **상태:** Step 2 — Design

---

## 변경 대상 파일

| 파일 | 변경 성격 |
|------|-----------|
| `VERSION` | 신규 추가 |
| `deploy.sh` | 수정 |

---

## Before → After

### `VERSION` (신규)

```
0.2.1
```

### `deploy.sh` — 버전 로드 및 배포

**Before**
```bash
# WikiCurate v0.2.1 Deployment Script
...
deploy_to() {
  local TARGET="$1"
  echo ">>> Deploying WikiCurate v0.2.1 to $TARGET..."
  ...
}
```

**After**
```bash
# WikiCurate Deployment Script
...
# 버전 로드
if [ ! -f "$SCRIPT_DIR/VERSION" ]; then
  echo "Error: VERSION file not found." >&2
  exit 1
fi
VERSION="$(cat "$SCRIPT_DIR/VERSION")"
...
deploy_to() {
  local TARGET="$1"
  echo ">>> Deploying WikiCurate v${VERSION} to $TARGET..."

  # 1. _system 배포
  ...

  # (기존 단계 이후) VERSION 파일 배포
  echo "5. VERSION 배포"
  run \cp "$SCRIPT_DIR/VERSION" "$TARGET/_system/VERSION"
  echo ""
  ...
}
```

### 배포 후 확인 방법

```bash
cat vault/_system/VERSION     # → 0.2.1
```

---

## 연계 룰/스킬 정합성

| 연계 | 결과 |
|------|------|
| `rsync -av --delete _system/` | `_system/VERSION`도 동기화 대상에 포함되므로 `cp` 없이 rsync만으로 자동 배포됨 — `cp` 단계 불필요, rsync가 처리 |
| `_system/` 내 기존 파일 | 충돌 없음 |

> **설계 조정:** `_system/VERSION`을 별도 `cp`로 배포하지 않고, `_system/` 디렉토리에 `VERSION`을 포함시켜 rsync가 자동으로 동기화하도록 한다. 이 방식이 더 단순하고 일관적이다.

---

## 미결 사항

없음.
