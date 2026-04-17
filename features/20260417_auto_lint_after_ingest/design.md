# Design: ingest 완료 후 자동 lint 실행

- **Feature ID:** `20260417_auto_lint_after_ingest`
- **작업 시작일:** 2026-04-17
- **상태:** Step 2 — Design

---

## 변경 대상 파일

| 파일 | 변경 성격 |
|------|-----------|
| `scripts/watch-ingest.sh` | 수정 — ingest 서브셸 내 lint 트리거 추가 |

---

## Before → After

### `scripts/watch-ingest.sh` — ingest 서브셸 내부

**Before**
```bash
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
) &
```

**After**
```bash
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
            sed 's/^/    /' "$lint_out"
        fi
        rm -f "$lint_out"
    fi
) &
```

---

## 실행 흐름

```
메인 타이머 루프 (sleep INTERVAL)
    └── 변경 감지 시 → 서브셸(&) [lock 보유]
            ├── ingest file1 → 성공/실패 로그
            ├── ingest file2 → 성공/실패 로그
            ├── 완료 요약 로그 (성공 N개, 실패 M개)
            └── ok > 0이면 → lint 실행 → 성공/실패 로그
                                           lock 해제
```

---

## 연계 룰/스킬 정합성

| 연계 | 결과 |
|------|------|
| `lint.md` 커맨드 변경 없음 | ✓ 기존 `/lint` 그대로 호출 |
| ingest lock 공유 | ✓ lint 종료 후 lock 해제 → 경쟁 조건 없음 |
| 타이머 스킵 동작 | ✓ lint 중 다음 주기 도래 시 "연기" 처리 — 의도된 동작 |

---

## 미결 사항

없음.
