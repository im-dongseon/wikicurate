대상 소스 파일: $ARGUMENTS

아래 순서로 ingest를 자동 수행한다.

1. 인자 처리:
   - 인자로 **디렉토리 경로**가 주어졌으면 그 경로를 wiki-inbox 위치로 사용한다.
   - 인자로 **파일 경로**가 주어졌으면:
     - raw/ 안의 파일이면 그대로 사용하고, 아래 Step 2(이동)를 건너뛴다.
     - wiki-inbox/ 안의 파일이면 아래 Step 2(이동)를 먼저 수행한다.
   - 인자가 없으면 (직접 실행 또는 배치):
     a. inbox 경로 결정:
        - 위키 루트의 .wikicurate 파일에 inbox_path 키가 있으면 그 경로를 inbox 위치로 사용한다.
        - 없으면 wiki-inbox/ (현재 루트 기준 상대경로)를 inbox 위치로 사용한다.
        - .wikicurate 없음 / 키 없음 / 파싱 실패 시 모두 wiki-inbox/ 로 fallback한다.
     b. 결정된 inbox 경로 직속 파일을 모두 찾는다 (maxdepth 1, error/ 제외).
     c. inbox 파일이 없으면 raw/에서 wiki/log.md에 기록되지 않은 파일을 찾는다 (이동 후 wiki 작성 실패한 파일 구제).
     d. 둘 다 없으면 "처리할 새 파일 없음"을 출력하고 종료한다.

2. wiki-inbox/ 파일 이동:
   각 wiki-inbox/ 파일을 raw/로 이동한다: `mv wiki-inbox/파일명 raw/파일명`

   중복 파일명 처리 정책 (raw/에 동일 파일명이 이미 존재하는 경우):
   → Skip 후 즉시 wiki-inbox/error/ 로 이동한다. 덮어쓰기 금지 (raw/ 불변 원칙).
   → "[SKIP] raw/파일명 이미 존재 — wiki-inbox/error/파일명 으로 이동" 출력.
   → "파일명을 변경한 뒤 wiki-inbox/에 다시 넣으세요." 안내.
   이동 실패 시 해당 파일을 건너뛰고 다음 파일을 처리한다.
   이후 단계는 raw/ 경로 기준으로 진행한다.

3. 각 파일에 대해 순서대로 처리한다:
   a. 파일 내용을 읽는다.
   b. `wiki/sources/`에 요약 페이지를 작성한다 (프론트매터 포함).
   c. 연관된 entity·concept 페이지를 생성하거나 갱신한다. 기존 내용과 충돌 시 해당 페이지에 명시한다.
   d. `wiki/index.md`를 갱신한다.
   e. `wiki/log.md` 끝에 추가한다: `## [오늘날짜] ingest | 파일명`
4. 처리 완료된 파일 목록과 변경된 wiki 페이지 수를 요약 출력한다.
