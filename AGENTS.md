# Meta-Instructions for AI Agents (System Maintainer Guide) v0.1.0

이 파일은 `WikiCurate` 시스템 자체를 **설계, 개발, 배포**하는 시스템 메인테이너(Maintainer)가 작업 전 반드시 참고해야 할 최상위 거버넌스 지침입니다.

## 1. 시스템 아키텍처 원칙 (Separation of Concerns)

- **Development Zone (Root):** 시스템을 만드는 공장입니다. `features/`, `releases/`, `deploy.sh` 및 이 가이드가 포함됩니다.
- **Operations Zone (`_system/`):** 시스템이 돌아가는 엔진입니다. 정본 룰과 스킬만 포함하며, 에이전트 운영 모드에서만 활성화됩니다.
- **물리적 격리:** 모든 신규 개발은 루트의 `features/`에서 격리되어 진행되며, 검증 완료 후 `deploy.sh`를 통해서만 `_system/`으로 주입됩니다.

## 2. 기능 기반 개발 플로우 (Feature-based Workflow)

모든 시스템 변경은 아래의 독립적인 단계를 거칩니다.

### 플로우 개요

[Step 1: Analysis] → [Step 2: Design] → [Step 3: Implementation]
                                              ↓ (결함 발견 시)
[Step 5: Deployment] ← [Step 4: Review] ←──┘
         ↑                    │
         └──── 승인 시 배포 ──┘
                              │ 결함 발견 시
                              ↓
                    Step 2 또는 Step 3으로 복귀
                    (복귀 이력을 review.md 변경 이력에 기록)

### Step 1: Analysis (분석)
- **진입 조건:** 새로운 요구사항 또는 기존 룰의 결함이 식별된 상태
- **활동:** 요구사항 분석, 현재 룰의 결함 및 영향 범위 파악
- **산출물:** `features/[YYYYMMDD]_[feat_id]/analysis.md`
- **종료 조건:** analysis.md에 아래 항목이 모두 작성된 경우
  - [ ] 배경 및 목적
  - [ ] 현행 진단 (결함 목록 및 근거)
  - [ ] 개정 범위 결정 (대상 파일, 변경 성격)
  - [ ] 이 Feature의 성공 기준 (Definition of Done)

### Step 2: Design & Review (설계 및 승인)
- **진입 조건:** Step 1의 analysis.md 종료 조건이 충족된 상태
- **활동:** 구체적인 규칙 변경안(Design) 작성 및 사용자 승인 획득
- **산출물:** `features/[YYYYMMDD]_[feat_id]/design.md`
- **종료 조건:** 사용자가 design.md의 변경안을 명시적으로 승인한 상태
- **에스컬레이션:** 변경이 기존 룰과 논리적 충돌을 일으키거나
  영향 범위가 불분명할 경우 구현 전 반드시 사용자 확인을 받는다.

#### design.md 필수 포함 항목
- 개정 전/후 비교 (Before → After)
- 대상 파일 및 변경 성격 (추가/수정/삭제)
- 연계 룰/스킬 정합성 검토
- 미결 사항 (Unresolved Issues) — 없으면 "없음" 명시

### Step 3: Implementation (구현)
- **진입 조건:** Step 2의 design.md가 사용자 승인된 상태
- **활동:** design.md를 기준으로 `_system/commands/`의 개별 명령어 또는 `_system/wiki-schema.md`를 직접 수정하거나 신규 작성합니다.
- **산출물:** `_system/commands/*.md` 또는 `_system/wiki-schema.md`
- **종료 조건:** design.md의 모든 변경 항목이 `_system/` 내의 정본 파일에 반영된 상태
- **자가 검증:** 작성 완료 후 아래를 직접 확인
  - `wiki-schema.md`와의 정합성 (지식 모델 정의 준수)
  - `commands/` 내 명령어 간 논리적 충돌 없음
  - 수정 사항이 `_system/SCHEMA.md`의 전체 구조를 해치지 않는지 확인

### Step 4: Review (검토 및 보고)
- **진입 조건:** Step 3의 종료 조건이 충족된 상태
- **활동:** design.md 기준으로 구현 결과를 검증하고 미반영 사항 보고
- **산출물:** `features/[YYYYMMDD]_[feat_id]/review.md`
- **종료 조건:** 아래 DoD 체크리스트가 모두 충족된 상태

#### Step 4 DoD 체크리스트 (review.md 필수 포함)

| 검증 항목 | 충족 여부 |
|-----------|-----------|
| design.md의 모든 변경 항목이 implementation에 반영됨 | [ ] |
| `_system/` 내 기존 파일과 충돌(중복 정의)이 없음 | [ ] |
| 새 명령이 참조하는 다른 파일이 실제로 존재함 | [ ] |
| `wiki/index.md` 등 내비게이션 갱신 필요 여부 확인 | [ ] |
| 미반영 항목이 있다면 사유와 후속 Feature ID가 명시됨 | [ ] |
| 연계 룰/스킬과의 정합성이 확인됨 | [ ] |

#### 반복 리뷰 시 처리 방법
- 결함 발견 → Step 3(Implementation)으로 복귀하여 수정
- 설계 자체의 결함 → Step 2(Design)로 복귀하여 design.md 개정 후 재승인
- 복귀할 때마다 review.md의 **변경 이력 테이블**에 버전(vN), 날짜, 복귀 사유를 기록

```markdown
| 버전 | 일자 | 주요 변경 |
|------|------|----------|
| v1 | YYYY-MM-DD | 초안 리뷰 |
| v2 | YYYY-MM-DD | [결함 A] 반영 후 재리뷰 |
```

### Step 5: Deployment (배포)
- **진입 조건:** Step 4의 DoD 체크리스트가 모두 충족되고 사용자 최종 승인된 상태
- **활동:** `deploy.sh` 스크립트를 실행하여 시스템 정본을 `DEPLOY_PATHS`에 정의된 경로들로 배포합니다.
  - `_system/` 디렉토리 전체를 `$TARGET/_system/`으로 동기화 (rsync)
  - `AGENTS.md`를 `$TARGET` 루트로 심볼릭 링크 생성 (points to `_system/wiki-schema.md`)
  - Claude Code용 명령어 경로를 심볼릭 링크로 연결 (`.claude/commands` -> `../_system/commands`)
- **종료 조건:** 배포 대상 경로 내에 최신 엔진과 명령어가 정상적으로 배치됨을 확인
- **에스컬레이션:** 배포 실패 시 대상 디렉토리 상태를 확인하고 `.env` 설정(특히 `DEPLOY_PATHS`)을 점검합니다.

## 3. 버전 관리 및 패치 정책

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
