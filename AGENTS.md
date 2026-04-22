# Meta-Instructions for AI Agents (System Maintainer Guide) v0.1.0

이 파일은 `WikiCurate` 시스템 자체를 **설계, 개발, 배포**하는 시스템 메인테이너(Maintainer)가 작업 전 반드시 참고해야 할 최상위 거버넌스 지침입니다.

## 1. 시스템 아키텍처 원칙 (Separation of Concerns)

- **Development Zone (Root):** 시스템을 만드는 공장입니다. `features/`, `releases/`, `deploy.sh` 및 이 가이드가 포함됩니다.
- **Operations Zone (`_system/`):** 시스템이 돌아가는 엔진입니다. 정본 룰과 스킬만 포함하며, 에이전트 운영 모드에서만 활성화됩니다.
- **물리적 격리:** 모든 신규 개발은 루트의 `features/`에서 격리되어 진행되며, 검증 완료 후 `deploy.sh`를 통해서만 `_system/`으로 주입됩니다.

## 2. 기능 기반 개발 플로우 (Feature-based Workflow)

모든 시스템 변경은 아래의 독립적인 단계를 거칩니다. 상세 방법론은 `docs/agent_dev_guide.md`를 참조한다.

### 플로우 개요

```
                   피드백 반영
              ┌───────────────────┐
              ↓                   │
[Step 1] Analysis → [Step 2] Design → [리뷰어/사용자 검토]
                         ↓ (승인)
                   [Step 3] Implementation
                         ↓
                   [Step 4] Review ──→ 결함 복귀
                         │             (범위 내: Step 2/3)
                         │             (범위 초과: 새 Feature)
                         ↓ (결함 없음)
                   [Step 5] Deployment
```

### Step 1: Analysis (분석)

**도구**: Claude Code CLI / Superpowers (선택 — 명시 요청 시만)  
**산출물**: `features/[YYYYMMDD]_[feat_id]/analysis.md`

**실행**:
```
"[기능 추가 / 수정] 계획에 따라서 시작해"
→ 에이전트가 analysis.md 작성
→ "바로 진행": Step 2 자동 시작 / "검토할게요": 피드백 반영 후 진행
```

필수 포함 항목:
- [ ] 배경 및 목적
- [ ] 현행 진단 (결함 목록 및 근거)
- [ ] 개정 범위 결정 (대상 파일, 변경 성격)
- [ ] Definition of Done (성공 기준)

### Step 2: Design (설계)

**도구**: Claude Code CLI / Superpowers (선택)  
**산출물**:
- `features/[YYYYMMDD]_[feat_id]/design.md` — 설계 결과물
- `features/[YYYYMMDD]_[feat_id]/design_review_N.md` — 설계 검토 피드백 (리뷰어별)

필수 포함 항목:
- 개정 전/후 비교 (Before → After)
- 대상 파일 및 변경 성격 (추가/수정/삭제)
- 연계 룰/스킬 정합성 검토
- 미결 사항 — 없으면 "없음" 명시

**design.md 버전 관리**: 피드백 반영 시 파일 내 섹션으로 이력 관리 (`## v1`, `## v2` …)  
**승인 마커**: 사용자 승인 시 파일 상단에 `approved: YYYY-MM-DD` 추가

**종료 조건**: 사용자의 명시적 승인 (필수, 생략 불가)
- `"승인. Step 3 진행해줘"` 또는 `"구현 시작해줘"` → Step 3 진행

### Step 3: Implementation (구현)

**도구**: Claude Code CLI  
**진입 조건**: design.md에 `approved:` 마커가 있는 상태  
**활동**: design.md를 기준으로 `_system/commands/`의 개별 명령어 또는 `_system/wiki-schema.md`를 직접 수정하거나 신규 작성합니다.  
**산출물**: `_system/commands/*.md` 또는 `_system/wiki-schema.md`  
**종료 조건**: design.md의 모든 변경 항목이 `_system/` 내의 정본 파일에 반영된 상태

**실행**:
```
"design.md를 참조해서 명시된 항목 구현해줘.
설계서에 없는 추가 변경은 하지 말 것"
```

자가 검증:
- [ ] `wiki-schema.md`와의 정합성 (지식 모델 정의 준수)
- [ ] `commands/` 내 명령어 간 논리적 충돌 없음
- [ ] 수정 사항이 `_system/` 전체 구조를 해치지 않는지 확인

### Step 4: Review (검토)

**도구**: 멀티모델 리뷰 **(필수 — 생략 불가)**  
**산출물**: `features/[YYYYMMDD]_[feat_id]/code_review_N.md` (리뷰어별)

DoD 체크리스트:
- [ ] design.md의 모든 변경 항목이 반영됨
- [ ] `_system/` 내 기존 파일과 충돌(중복 정의)이 없음
- [ ] 새 명령이 참조하는 파일이 실제로 존재함
- [ ] `wiki/index.md` 등 내비게이션 갱신 여부 확인
- [ ] 결함 처리 완료 (→ 리뷰 공통 규칙의 '결과 처리' 참조)
- [ ] 연계 룰/스킬과의 정합성 확인

### Step 5: Deployment (배포)

**진입 조건**: Step 4 DoD 전항목 충족 + 사용자 최종 승인 (`"배포 진행해줘"`)  
**활동**: `deploy.sh` 스크립트를 실행하여 시스템 정본을 `DEPLOY_PATHS`에 정의된 경로들로 배포합니다.
  - `_system/` 디렉토리 전체를 `$TARGET/_system/`으로 동기화 (rsync)
  - `AGENTS.md`를 `$TARGET` 루트로 심볼릭 링크 생성 (points to `_system/wiki-schema.md`)
  - Claude Code용 명령어 경로를 심볼릭 링크로 연결 (`.claude/commands` -> `../_system/commands`)

**산출물**: `features/HISTORY.md` — 배포 후 에이전트가 자동으로 항목 append

**HISTORY.md 항목 형식**:
```markdown
## [YYYY-MM-DD] feat_id

- **목적**: 무엇을 해결/추가했는가
- **로직**: 어떤 방식으로 구현했는가
- **결정 이유**: 왜 이 방식을 선택했는가 (대안 대비)
- **트레이드오프**: 이 결정으로 포기한 것, 생긴 제약 (없으면 "없음")
- **결론**: 최종 상태 및 후속 과제
- **참조**: features/[YYYYMMDD]_[feat_id]/
```

**에스컬레이션**: 배포 실패 시 대상 디렉토리 상태를 확인하고 `.env` 설정(특히 `DEPLOY_PATHS`)을 점검합니다.

---

## 3. 리뷰 공통 규칙

Step 2(설계 검토)와 Step 4(구현 검토)에 동일하게 적용한다.

| 단계 | 파일명 | 리뷰어 예시 |
|---|---|---|
| Step 2 Design Review | `design_review_N.md` | `design_review_1.md` (Claude), `design_review_2.md` (Gemini) … |
| Step 4 Code Review | `code_review_N.md` | `code_review_1.md` (Claude), `code_review_2.md` (Gemini) … |

**리뷰어 구성**: 2개 이상 권장 (독립성 + 다양성이 핵심)

| 리뷰어 | 실행 방법 |
|---|---|
| Claude (컨텍스트 초기화) | 새 터미널 탭에서 `claude` 실행 |
| Gemini | `gemini` CLI 또는 웹에서 별도 세션 |
| Codex | `codex` CLI 또는 웹에서 별도 세션 |
| 서브에이전트 | `"서브에이전트로 리뷰해서 code_review_N.md에 기록해줘"` |

**컨텍스트 전달**:
```bash
git diff $(git merge-base HEAD main) > review_context.md
```

**결과 취합**:
```
리뷰 파일 1개: "[prefix]_review_1.md를 참조해서 지적 항목 우선순위 정리해줘"
리뷰 파일 2개 이상: "공통으로 지적한 항목만 추려서 우선순위 정리해줘"
```

**결과 처리**:
- 설계 결함 → Step 2(Design)으로 복귀 후 재검토
- 구현 버그/로직 오류 → Step 3(Implementation)으로 복귀 후 재검토
- 범위 초과 결함 → 해당 리뷰 파일에 사유 기록 후 새 Feature ID 발급

---

## 4. 멀티에이전트 접근법

- **수동 오케스트레이션**: [cmux](https://cmux.com/ko)로 패널 분리 → 패널별로 다른 에이전트 실행
- **자동 오케스트레이션**: Claude Agent tool — `"두 에이전트가 병렬로 A는 성능, B는 보안 리뷰해줘"`

---

## 5. Git Worktree 활용

> 아래 조건에서 **필수** 적용:
> - 개발자·리뷰어를 동시에 별도 패널로 운용할 때
> - 서브에이전트 리뷰를 자동화할 때 (Claude Agent tool 활용 시)

```bash
# feature worktree 생성
git worktree add ../wikicurate-feat/[YYYYMMDD]_[feat_id] feature/[feat_id]

# 작업 완료 후 제거
git worktree remove ../wikicurate-feat/[YYYYMMDD]_[feat_id]
```

Agent tool의 `isolation: "worktree"` 옵션으로 서브에이전트가 자동으로 임시 worktree를 생성해 작업 후 결과만 반환한다.

---

## 6. Feature 디렉토리

```
features/
├── HISTORY.md                           # 배포 이력 누적 (append-only)
└── [YYYYMMDD]_[feat_id]/
    ├── analysis.md          # Step 1 산출물
    ├── design.md            # Step 2 산출물
    ├── design_review_N.md   # Step 2: 설계 검토, 리뷰어별
    └── code_review_N.md     # Step 4: 구현 검토, 리뷰어별
```

---

## 7. 버전 관리 및 패치 정책

- **Major/Minor/Patch:** 기능의 크기에 따라 버전을 승격합니다.
- **Atomic Change:** 하나의 Feature는 반드시 하나의 목적만 달성해야 합니다.
- **Traceability:** 모든 정본의 변경 사항은 `features/` 내의 분석 문서를 통해 근거를 추적할 수 있어야 합니다.

### 버전 명명 표준

| 용도 | 형식 | 예시 |
|------|------|------|
| 파일시스템 (사용중) | `_system/` 경로 고정 유지 | `_system/` |
| 문서·표기용 | `v{MAJOR}.{MINOR}.{PATCH}` | `v0.1.0` |
| 배포 도구 인자 | `{MAJOR}_{MINOR}_{PATCH}` 패턴 준수 | `0_1_0` |

### Feature 디렉토리 명명

```
features/[YYYYMMDD]_[feat_id]/
```

- `YYYYMMDD`: 작업 시작일 (KST)
- `feat_id`: 소문자 + 언더스코어, 기능을 간결히 표현 (예: `agents_methodology_refine`)

---
*일상적인 지식 관리(KMS) 운영 시에는 `_system/wiki-schema.md` (Operator Guide)로 전환하십시오.*
