# ansim_core

안심디디의 순수 Dart 엔진 (Flutter 의존성 없음 — 앱과 전처리 도구가 함께 사용).

- `SafetyModel` — 안심점수 = 0.55·조명 + 0.35·CCTV + 0.10·비상벨 (조명은 보안등 밀집도와 도로 등급별 가로등 추정치 중 큰 값)
- `FacilityStore` / `GridIndex` — 안전시설 격자 인덱스, 경로 주변 시설 집계
- `RoadGraph` — CSR 보행 도로망(바이너리 직렬화, 복사 없는 로드)
- `AStarRouter` — 비용 = 길이 × (1 + α·(1 − 안심점수)), α=0이면 최단 경로
- `SafeRoutePlanner` — 최단·안심 경로 계산 + 같은 기준 채점 + 대조 문구
- `SafetyHeatmap` — 화면 범위 밝기 격자

```bash
dart test
```
