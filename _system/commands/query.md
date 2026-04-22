질문: $ARGUMENTS

아래 순서로 질의를 수행한다.

1. 관련 페이지를 탐색한다:
   - `graphify-out/GRAPH_REPORT.md`가 존재하면 먼저 읽어 god nodes와 community 구조를 파악한다.
   - `graphify-out/graph.json`이 존재하면 질의 키워드와 연관된 노드를 시작점으로 **1-hop 인접 노드**를 추출한다.
   - 둘 다 없으면 `wiki/index.md`로 폴백한다. 폴백 시 사용자에게 알린다.
2. 추출된 페이지들을 읽고 답변을 합성한다. 각 클레임에 출처 페이지를 인용한다.
3. 답변을 사용자에게 제시한다.
4. 이 답변이 독립적인 분석 가치가 있다면 사용자에게 물어본 후 `wiki/analyses/`에 새 페이지로 저장한다.
5. `wiki/log.md` 끝에 추가한다: `## [오늘날짜] query | 질문 요약`
