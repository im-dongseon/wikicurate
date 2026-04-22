옵션: $ARGUMENTS

graphify CLI로 wiki 지식 그래프를 빌드한다.

## 사전 확인

graphify가 설치되어 있는지 확인한다:
```bash
command -v graphify || pip install graphifyy
```

## 빌드 절차

- `--update` 옵션이 있거나 `graphify-out/graph.json`이 이미 존재하면 증분 빌드:
  ```bash
  graphify update .
  ```
- 그 외 (최초 빌드):
  ```bash
  graphify .
  ```

## 완료 출력

빌드 완료 후 graph.json 및 GRAPH_REPORT.md 경로를 출력한다.
GRAPH_REPORT.md가 없으면 graphify 버전이 오래된 것이므로 `pip install -U graphifyy`를 안내한다.
