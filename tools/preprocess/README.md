# 데이터 전처리 (tools/preprocess)

공공데이터 원본과 OpenStreetMap 도로망을 앱 내장 바이너리로 변환합니다.
서버는 없고, 이 도구도 **빌드 전에 한 번** 개발자 PC에서만 실행합니다.

## 입력 (`rawdata/`, Git 제외)

| 경로 | 내용 | 출처 |
|---|---|---|
| `rawdata/lights/*.csv` | 부산 16개 구·군 보안등정보 (UTF-8) | data.go.kr 전국보안등정보표준데이터 (15017320) 의 구·군별 파일 |
| `rawdata/cctv/*.csv` | 부산광역시_방범용 CCTV 정보 (CP949) | data.go.kr 15082060 |
| `rawdata/bells/page*.json` | 전국안전비상벨위치표준데이터 (부산만 추림) | data.go.kr 15028206 |
| `rawdata/osm/busan_walk.json` | 부산 보행 가능 도로 | OpenStreetMap, Overpass API |

OSM 쿼리(자동차전용도로·고속도로·보행 금지 도로 제외):

```
[out:json][timeout:900];
area["name"="부산광역시"]["admin_level"="4"]["boundary"="administrative"]->.a;
way(area.a)["highway"]
  ["highway"!~"^(motorway|motorway_link|construction|proposed|raceway|bus_guideway|platform|elevator|via_ferrata|abandoned|escape|busway|services|rest_area)$"]
  ["motorroad"!="yes"]["foot"!~"^(no|private|use_sidepath)$"]["access"!~"^(no|private)$"]["area"!="yes"]->.w;
.w out body qt; node(w.w); out skel qt;
```

## 실행

```bash
cd tools/preprocess
dart run bin/preprocess.dart --raw ../../rawdata --out ../../app/assets/data
dart run bin/check_routes.dart   # 실제 부산 경로 몇 개로 결과 점검
```

## 출력 (`app/assets/data/`)

- `facilities.bin` — 시설 좌표·종류·가중치 (같은 좌표 병합)
- `graph.bin` — 보행 도로망 CSR 그래프 + 엣지별 조명·CCTV·비상벨 밀집도 + 도로 등급
- `meta.json` — 건수, 데이터 기준일, 출처·라이선스

포맷은 `packages/ansim_core/lib/src/facilities.dart`, `road_graph.dart` 주석 참고.
