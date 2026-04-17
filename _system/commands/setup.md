배포 후 초기 설정을 수행한다.

## 1. 환경 검증

아래 항목을 순서대로 확인한다. 문제가 있으면 사용자에게 보고하고 계속 진행 여부를 묻는다.

- [ ] 현재 작업 디렉토리가 배포된 vault 루트인지 확인 (`CLAUDE.md` 또는 `AGENTS.md` 존재 여부로 판단)
- [ ] `raw/` 디렉토리 존재 확인. 없으면 생성한다.
- [ ] `wiki/` 및 하위 폴더(`sources/`, `entities/`, `concepts/`, `analyses/`) 존재 확인. 없으면 생성한다.
- [ ] `wiki/index.md` 존재 확인. 없으면 빈 index 파일을 생성한다.
- [ ] `wiki/log.md` 존재 확인. 없으면 빈 log 파일을 생성한다.

## 2. graphify 설치 확인

graphify가 설치되어 있는지 확인한다:
```bash
graphify --version
```

설치되어 있지 않으면 설치한다:
```bash
pip install graphifyy
graphify install
```

설치 후 재확인하고, 실패 시 사용자에게 수동 설치를 안내한다.

## 3. 초기 그래프 빌드

`wiki/` 디렉토리에 페이지가 있으면 전체 그래프를 빌드한다:
```bash
graphify wiki/
```
`graphify-out/graph.json`이 생성된다. wiki가 비어 있으면 이 단계를 건너뛴다.
