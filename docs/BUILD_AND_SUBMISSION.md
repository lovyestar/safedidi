# 빌드 및 제출 체크리스트 (안심디디)

## 1. API 키 준비 (지도는 키 불필요)

`app/keys.example.json` → `app/keys.json` 으로 복사 후 입력 (Git 제외됨).

| 키 | 용도 | 없으면 |
|---|---|---|
| `KAKAO_REST_API_KEY` | 출발·도착 장소 검색 | 검색 불가 |
| `TMAP_APP_KEY` | 일반(최단) 보행 경로 | 앱 내장 최단 경로로 대체 |

```text
[ ] Kakao Developers → 내 애플리케이션 → 앱 키 → REST API 키
    (로컬 API 권한 오류가 나면 앱 설정에서 카카오맵/로컬 사용 설정 확인)
[ ] SK open API(openapi.sk.com) → TMAP → 앱 생성 → appKey (선택)
[ ] 서버가 없어 키는 APK 안에 들어감 → 각 콘솔에서 사용량 한도·패키지 제한 설정 권장
```

## 2. 실행 (에뮬레이터·실기기)

```bash
cd app
flutter pub get
flutter run --dart-define-from-file=keys.json
```

Android Studio: `app` 폴더 열기 → Run 설정(Edit Configurations) → **Additional run args** 에
`--dart-define-from-file=keys.json` 입력 → ▶ Run.

- 에뮬레이터 위치: Extended Controls(⋯) → Location 에서 부산 좌표(예: 35.1577, 129.0594) 지정
- 현재 위치가 부산 밖이면 출발지를 검색해서 지정

## 3. 릴리스 APK

```bash
cd app
flutter build apk --release --dart-define-from-file=keys.json
# 결과: app/build/app/outputs/flutter-apk/app-release.apk
```

- 현재 release 서명은 디버그 키(템플릿 기본값). 스토어 배포 시 별도 keystore로 교체.
- 지도는 OpenStreetMap 타일(키 불필요). 공모전 시연 규모는 문제없지만, 정식 배포로 사용량이 많아지면 OSM 타일 정책상 별도 타일 서비스로 바꿔야 함.

## 4. 데이터 갱신 (선택)

`tools/preprocess/README.md` 참고. 원본을 `rawdata/`에 받고 전처리 → `app/assets/data/` 갱신 → 다시 빌드.

## 5. 최종 제출 폴더

```text
안심디디.apk
안심디디_소스코드.zip      (rawdata/, build/, keys.json 제외)
안심디디_발표자료.pptx
시연영상.mp4
README.md
```

## 발표 유의 문구

- 안심지수는 공공 안전시설 위치 기반 참고 지표이며 실제 안전을 보장하지 않습니다.
- CCTV는 설치 위치 정보이며 실시간 영상·작동 여부를 의미하지 않습니다.
- 공개 데이터의 보안등은 주로 폭 12m 미만 골목에 설치된 것이라, 대로의 도로 가로등은 도로 등급으로 보정합니다.
- 비상벨 공개 데이터는 부산 203건(2019~2020 기준)으로 적어 점수 비중을 10%로 낮췄습니다.
