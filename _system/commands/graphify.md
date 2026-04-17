옵션: $ARGUMENTS

wiki 관계 그래프를 빌드한다. **Claude가 직접 wiki 파일을 읽고 `graph.json`을 생성한다** (별도 CLI 없음).

## 빌드 절차

1. `wiki/` 하위 모든 `.md` 파일 목록을 수집한다 (`index.md`, `log.md` 제외).
2. 각 파일에 대해:
   a. 프론트매터에서 `title`, `tags`를 추출한다.
   b. 본문 첫 비어있지 않은 단락을 `description`으로 추출한다 (100자 이내로 잘라낸다).
   c. 본문의 `[[링크 텍스트]]` 패턴을 파싱해 엣지 목록을 구성한다.
3. `graphify-out/` 디렉토리가 없으면 생성한다.
4. `graphify-out/graph.json`을 아래 스키마로 작성한다:

```json
{
  "meta": {
    "built_at": "<현재 시각, ISO 8601 로컬 타임존>",
    "node_count": <정수>,
    "edge_count": <정수>,
    "source": "wiki/"
  },
  "nodes": [
    {
      "id": "<title 값>",
      "label": "<title 값>",
      "type": "<파일 경로의 카테고리: sources|entities|concepts|analyses>",
      "file": "<wiki/ 기준 상대 경로>",
      "tags": ["태그1", "태그2"],
      "description": "<본문 첫 단락 100자 이내>"
    }
  ],
  "edges": [
    {
      "source": "<노드 id>",
      "target": "<노드 id>",
      "relation": "links_to"
    }
  ]
}
```

> `built_at`은 반드시 실제 현재 시각을 사용한다. 임의값 사용 금지.  
> 엣지의 `target`이 존재하지 않는 노드를 가리키면 엣지를 생략한다.

## `--update` 모드

`--update` 옵션이 주어지고 `graph.json`이 이미 존재하면 증분 빌드를 수행한다:

- `meta.built_at` 이후에 수정된 파일만 재처리한다.
- 해당 노드의 `tags`, `description`을 갱신하고 연결된 엣지를 재계산한다.
- 변경되지 않은 노드·엣지는 그대로 유지한다.
- `meta.built_at`과 `node_count`, `edge_count`를 업데이트한다.

`graph.json`이 없으면 `--update`여도 전체 빌드를 수행한다.

## 완료 출력

빌드 완료 후 노드 수와 엣지 수를 출력한다.
