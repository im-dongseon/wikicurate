# Analysis: VERSION 파일 기반 버전 관리

- **Feature ID:** `20260417_version_file`
- **작업 시작일:** 2026-04-17
- **상태:** Step 1 — Analysis

---

## 배경 및 목적

현재 버전 정보가 여러 파일에 하드코딩되어 있고, 배포 후 대상 볼트에서 어떤 버전이
배포됐는지 확인할 방법이 없다. `VERSION` 파일을 단일 소스로 두고 배포 시 대상에
복사함으로써 버전 추적을 일관되게 한다.

## 현행 진단

| 항목 | 현재 상태 | 문제 |
|------|-----------|------|
| 버전 소스 | `deploy.sh`, `README.md`, `README.en.md`, `CHANGELOG.md`에 각각 하드코딩 | 버전 업데이트 시 누락 위험 |
| 배포 후 확인 | 불가 | 볼트에 버전 정보 없음 |
| `_system/wiki-schema.md` | 버전 정보 없음 | — |

## 개정 범위 결정

| 파일 | 변경 성격 | 사유 |
|------|-----------|------|
| `VERSION` | 신규 추가 | 단일 버전 소스 |
| `deploy.sh` | 수정 | `VERSION` 파일에서 읽고, `$TARGET/_system/VERSION`으로 복사 |
| `README.md` / `README.en.md` | 수정 | 버전 배지를 `VERSION` 파일 기준으로 정렬 (수동 관리 유지, 단 버전 일치 확인) |

## 이 Feature의 성공 기준 (Definition of Done)

- [ ] `VERSION` 파일이 단일 소스로 존재함
- [ ] `deploy.sh`가 `VERSION`을 읽어 배포 메시지에 출력함
- [ ] 배포 후 `$TARGET/_system/VERSION`이 존재하고 올바른 버전을 담고 있음
- [ ] 버전 불일치 시 (`VERSION` 파일 없음) 배포가 오류로 종료됨
