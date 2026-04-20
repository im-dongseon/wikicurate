배포 후 초기 설정을 수행한다.

## 1. 환경 검증

아래 항목을 순서대로 확인한다. 문제가 있으면 사용자에게 보고하고 계속 진행 여부를 묻는다.

- [ ] 현재 작업 디렉토리가 배포된 vault 루트인지 확인 (`CLAUDE.md` 또는 `AGENTS.md` 존재 여부로 판단)
- [ ] `raw/` 디렉토리 존재 확인. 없으면 생성한다.
- [ ] `wiki/` 및 하위 폴더(`sources/`, `entities/`, `concepts/`, `analyses/`) 존재 확인. 없으면 생성한다.
- [ ] `wiki/index.md` 존재 확인. 없으면 빈 index 파일을 생성한다. **이미 존재하면 내용을 유지하고 건너뛴다.**
- [ ] `wiki/log.md` 존재 확인. 없으면 빈 log 파일을 생성한다. **이미 존재하면 내용을 유지하고 건너뛴다.** (append-only 이력 파일 — 절대 덮어쓰지 않는다)

## 2. Python 의존성 확인

아래 패키지가 설치되어 있는지 확인한다. 미설치 시 설치 후 계속 진행한다.

| 패키지 | 용도 | 설치 명령 |
|--------|------|----------|
| `openpyxl` | XLSX 메타데이터 추출 | `pip3 install openpyxl` |
| `python-pptx` | PPTX 텍스트 추출 | `pip3 install python-pptx` |
| `python-docx` | DOCX 텍스트 추출 | `pip3 install python-docx` |

```bash
pip3 show openpyxl python-pptx python-docx
```

## 3. Google 파일 연동 설정 (선택)

`.gsheet`, `.gdoc`, `.gslides` 파일을 처리할 경우에만 설정한다. 미설정 시 인증 없이 URL만 기록하는 fallback으로 동작한다.

### 패키지 설치

| 패키지 | 용도 | 설치 명령 |
|--------|------|----------|
| `gspread` | Google Sheets 접근 | `pip3 install gspread` |
| `google-api-python-client` | Google Docs/Slides 접근 | `pip3 install --upgrade google-api-python-client` |
| `google-auth-oauthlib` | OAuth 2.0 사용자 인증 | `pip3 install google-auth-oauthlib` |

```bash
pip3 show gspread google-api-python-client google-auth-oauthlib
```

### OAuth 프로필 설정

1. [GCP 콘솔](https://console.cloud.google.com)에서 프로젝트 생성 후 **Drive API** 활성화
2. **OAuth 동의 화면** 구성 (External, `auth/drive.readonly` 스코프 추가)
3. **사용자 인증 정보** → OAuth 2.0 클라이언트 ID 생성 (데스크톱 앱) → **JSON 다운로드**
4. 다운로드한 키 파일을 프로필명(`personal`, `work` 등)과 함께 아래 경로에 저장:
```bash
mkdir -p ~/.config/wikicurate
mv ~/Downloads/client_secret_xxxx.json ~/.config/wikicurate/client_secret_{profile}.json
```
5. 위키 루트에 `.wikicurate` 파일을 생성하고 프로필을 지정한다:
```json
{
  "google_profile": "{profile}"
}
```
6. 최초 실행 시 브라우저가 열리며 인증을 수행한다. 이후 `token_{profile}.pickle`이 자동 생성/갱신된다.

## 4. graphify 설치 확인

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

## 5. 그래프 빌드

wiki가 비어 있으면 이 단계를 건너뛴다.

`wiki/` 디렉토리에 페이지가 있고 그래프 빌드가 필요한 경우 아래 명령을 직접 실행한다:
```bash
graphify wiki/
```
`graphify-out/graph.json`이 생성된다.
