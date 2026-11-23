# BeAT(부산교육 AI 튜터) 활용 — 다국어 길 안내 검수

안심디디의 영어·일본어 길 안내 문구는 앱 개발 중에 먼저 만들었습니다(`packages/ansim_core/lib/src/guide_lang.dart`, `app/lib/ui/guide_text.dart`).
BeAT에게 아래 질문을 차례로 하고, 답을 받아 문구를 고친 뒤 그 과정을 기록합니다.

- 접속: BeAT(교육디지털원패스 로그인)
- 순서: 질문 1(번역 검수) → 질문 2(도로 이름 로마자) → 질문 3(외국인 사용자 시나리오) → 질문 4(검수 에이전트 만들기, 선택)
- 각 질문은 아래 상자 안의 글을 그대로 붙여넣으면 됩니다. 질문 1은 맨 아래 **문구표**를 함께 붙여넣습니다.

---

## 질문 1 · 길 안내 문구 번역 검수

```text
너는 지도 앱 도보 내비게이션의 음성 안내 문구를 다듬는 영어·일본어 현지화 전문가야.

나는 부산의 밤길에서 보안등·CCTV가 많은 밝은 길로 안내하는 앱 "안심디디"를 만들고 있어.
외국인 유학생과 관광객도 쓸 수 있게 길 안내를 영어와 일본어로 만들었는데,
아래 문구표의 영어(en)·일본어(ja)가 자연스러운지 검수해 줘.

검수 기준
1. 실제 지도 앱(영어: Google Maps 도보 안내, 일본어: Google マップ·NAVITIME 도보 안내)에서 쓰는 말투일 것
2. 음성(TTS)으로 들었을 때 짧고 바로 이해될 것. 걸으면서 듣는 안내라 한 문장은 짧게
3. 같은 뜻은 같은 낱말로(예: 왼쪽 = left / 左, 목적지 = destination / 目的地)
4. 화면 글자(카드 제목)는 3~4단어 안쪽
5. {거리}, {분}, {점수} 같은 중괄호 부분은 그대로 둘 것

결과는 아래 표 형식으로만 줘. 바꿀 필요가 없으면 "수정 없음"이라고 써.

| 번호 | 지금 en | 고친 en | 지금 ja | 고친 ja | 고친 이유(한국어로 한 줄) |
```

## 질문 2 · 도로 이름 로마자 표기 확인

```text
영어·일본어 안내 화면에서 한국 도로 이름을 로마자로 보여주려고 해.
국어의 로마자 표기법과 도로명주소 영문 표기 방식(예: 중앙대로 → Jungang-daero, 783번길 → 783beon-gil)에 맞는지 확인해 줘.
틀린 것만 고쳐서 "원래 이름 | 지금 표기 | 맞는 표기 | 이유" 표로 알려 줘.

중앙대로 → Jungang-daero
중앙대로783번길 → Jungang-daero 783beon-gil
전포대로199번길 → Jeonpo-daero 199beon-gil
우동1로20번길 → Udong 1-ro 20beon-gil
서전로 → Seojeon-ro
서면로 → Seomyeon-ro
동천로 → Dongcheon-ro
태종로 → Taejong-ro
중동길1번길 → Jungdong-gil 1beon-gil
장전온천천로83번길 → Jangjeononcheoncheon-ro 83beon-gil

참고: 지금 방식은 글자를 하나씩 옮기고 받침 뒤 모음만 이어 읽어(연음). 신라→Silla 같은 자음 동화는 반영하지 않아.
동화를 반영하지 않아서 틀리는 경우가 실제 부산 도로 이름에 많은지도 알려 줘.
```

## 질문 3 · 외국인 사용자 시나리오 점검

```text
부산 서면에서 밤 11시에 숙소로 걸어가는 일본인 관광객과, 처음 부산에 온 영어권 유학생이 되어 줘.
아래는 안심디디가 실제로 말하는 안내 순서야(영어·일본어 각각).

[영어]
Starting safe route guidance. About 10 minutes, 703 meters, safety score 44. Go straight for 536 meters on Jungang-daero.
In 40 meters, keep slightly left
Keep slightly left
In 50 meters, you will reach your destination. It is on the left.
Your destination is on the left
You have arrived. Your destination is on the left.

[일본어]
安心ルートの案内を開始します。約10分、703メートル、安心指数は44点です。536メートル直進してください。
40メートル先、斜め左方向です
斜め左方向です
50メートル先、目的地です。目的地は左側です。
目的地は左側です
目的地に到着しました。目的地は左側です。

각 사용자 입장에서
1. 헷갈리거나 불안하게 느껴질 수 있는 표현
2. "safety score(安心指数)"처럼 설명 없이 들으면 뜻을 모를 수 있는 말과, 짧은 대안
3. 밤길 안전을 위해 안내에 꼭 들어가면 좋을 한 문장(있다면)
을 사용자별로 3개 이내로 알려 줘.
```

## 질문 4 · 검수 에이전트 만들기 (BeAT AI Agents, 선택)

BeAT의 AI Agents 메뉴에서 새 에이전트를 만들고 아래를 지시문으로 넣습니다. 자료로 이 문서의 **문구표**를 올립니다.

```text
이름: 안심디디 다국어 안내 검수 도우미
역할: 도보 내비게이션 안내 문구(한국어·영어·일본어)를 검수하는 현지화 도우미
규칙:
- 올린 문구표의 표현과 용어를 기준으로 답한다.
- 새 문구를 받으면 같은 표의 기존 말투·용어와 맞는지 먼저 확인한다.
- 걸으면서 듣는 음성이므로 한 문장은 짧게, 명령형·안내형으로 쓴다.
- 결과는 "번호 | 고친 en | 고친 ja | 이유" 표로만 준다.
```

---

## 받은 답을 앱에 반영하는 방법

1. BeAT가 준 표를 그대로 복사해 둡니다.
2. 고칠 문구를 `guide_lang.dart`(음성·안내 카드 문장)와 `guide_text.dart`(안내 화면 글자)에서 바꿉니다.
3. `cd packages/ansim_core && dart test`로 안내 문장 테스트를 돌리고, 바뀐 문장에 맞춰 테스트 기대값도 고칩니다.
4. 아래 기록표를 채웁니다(공모전 포트폴리오용).

| 날짜 | 질문 | BeAT 답 요약 | 앱에 반영한 것 | 화면·커밋 |
| --- | --- | --- | --- | --- |
| | 질문 1 | | | |
| | 질문 2 | | | |
| | 질문 3 | | | |

---

## 문구표 (질문 1에 함께 붙여넣기)

### 회전·길 특징

| 번호 | 쓰임 | ko | en | ja |
| --- | --- | --- | --- | --- |
| 1 | 카드: 직진 | 직진 | Go straight | 直進 |
| 2 | 카드: 살짝 왼쪽 | 11시 방향 | Slight left | 斜め左 |
| 3 | 카드: 왼쪽 | 좌회전 | Turn left | 左折 |
| 4 | 카드: 크게 왼쪽 | 8시 방향 | Sharp left | 大きく左 |
| 5 | 카드: 유턴 | 유턴 | U-turn | Uターン |
| 6 | 카드: 살짝 오른쪽 | 1시 방향 | Slight right | 斜め右 |
| 7 | 카드: 오른쪽 | 우회전 | Turn right | 右折 |
| 8 | 카드: 크게 오른쪽 | 4시 방향 | Sharp right | 大きく右 |
| 9 | 음성: 살짝 왼쪽 | 11시 방향입니다 | Keep slightly left | 斜め左方向です |
| 10 | 음성: 왼쪽 | 왼쪽 방향입니다 | Turn left | 左方向です |
| 11 | 음성: 크게 왼쪽 | 왼쪽 방향입니다 | Turn sharply left | 大きく左方向です |
| 12 | 음성: 유턴 | 뒤로 돌아가세요 | Turn around | Uターンしてください |
| 13 | 음성: 살짝 오른쪽 | 1시 방향입니다 | Keep slightly right | 斜め右方向です |
| 14 | 음성: 오른쪽 | 오른쪽 방향입니다 | Turn right | 右方向です |
| 15 | 음성: 크게 오른쪽 | 오른쪽 방향입니다 | Turn sharply right | 大きく右方向です |
| 16 | 카드: 횡단보도 | 횡단보도 건너기 | Cross the crosswalk | 横断歩道を渡る |
| 17 | 카드: 육교 | 육교 건너기 | Cross the footbridge | 歩道橋を渡る |
| 18 | 카드: 지하도 | 지하도 이용 | Take the underpass | 地下道を通る |
| 19 | 카드: 계단 | 계단 이용 | Take the stairs | 階段を利用 |
| 20 | 음성: 횡단보도 | 횡단보도를 건너세요 | Cross the crosswalk | 横断歩道を渡ってください |
| 21 | 음성: 육교 | 육교를 건너세요 | Cross the footbridge | 歩道橋を渡ってください |
| 22 | 음성: 지하도 | 지하도를 이용하세요 | Take the underpass | 地下道を通ってください |
| 23 | 음성: 계단 | 계단을 이용하세요 | Take the stairs | 階段を利用してください |
| 24 | 카드: 회전+횡단보도 | 좌회전 후 횡단보도 건너기 | Turn left, then cross the crosswalk | 左折して横断歩道を渡る |
| 25 | 음성: 회전+횡단보도 | 왼쪽 방향, 횡단보도를 건너세요 | Turn left, then cross the crosswalk | 左方向、横断歩道を渡ってください |

### 문장

| 번호 | 쓰임 | ko | en | ja |
| --- | --- | --- | --- | --- |
| 26 | 약 50m 전 | 잠시 후 왼쪽 방향입니다 | In {거리} meters, turn left | {거리}メートル先、左方向です |
| 27 | 바로 이어지는 안내 | 왼쪽 방향입니다, 이어서 횡단보도를 건너세요 | Turn left, then cross the crosswalk | 左方向です。その先、横断歩道を渡ってください |
| 28 | 안내 시작 | 안심 경로 안내를 시작합니다. 약 {분}분, {거리}미터 거리이고 안심지수는 {점수}점입니다. 중앙대로를 따라 {거리}미터 직진하세요. | Starting safe route guidance. About {분} minutes, {거리} meters, safety score {점수}. Go straight for {거리} meters on Jungang-daero. | 安心ルートの案内を開始します。約{분}分、{거리}メートル、安心指数は{점수}点です。{거리}メートル直進してください。 |
| 29 | 목적지 50m 전 | 잠시 후 목적지입니다. 목적지는 왼쪽에 있습니다 | In {거리} meters, you will reach your destination. It is on the left. | {거리}メートル先、目的地です。目的地は左側です。 |
| 30 | 목적지 15m 전 | 목적지는 왼쪽에 있습니다 | Your destination is on the left | 目的地は左側です |
| 31 | 도착 | 목적지에 도착했어요. 목적지는 왼쪽에 있어요. | You have arrived. Your destination is on the left. | 目的地に到着しました。目的地は左側です。 |
| 32 | 도착(방향 모름) | 목적지에 도착했어요. 오늘도 안전한 귀가였어요. | You have arrived. Get home safe! | 目的地に到着しました。お疲れさまでした。 |
| 33 | 경로 이탈 후 재탐색 | 경로를 벗어나 현재 위치에서 안심 경로를 다시 찾았어요. | You left the route. Found a new safe route from your current location. | ルートを外れたため、現在地から安心ルートを再検索しました。 |
| 34 | 도착 예정 시간 지남 | 예상 도착 시간이 지났어요. 괜찮으세요? 화면을 확인해 주세요. | You're past your expected arrival time. Are you okay? Please check your screen. | 到着予定時刻を過ぎました。大丈夫ですか?画面を確認してください。 |

### 안내 화면 글자

| 번호 | 쓰임 | ko | en | ja |
| --- | --- | --- | --- | --- |
| 35 | 카드 아래 줄 | 그다음 | Then | その先 |
| 36 | 아주 가까움 | 곧 | Now | まもなく |
| 37 | 안내 없음 | 경로를 따라 이동하세요 | Follow the route | ルートに沿って進んでください |
| 38 | 목록: 출발 | 출발 · {도로} 방면 | Start · Toward {도로} | 出発 · {도로}方面 |
| 39 | 목록: 도착 | 도착 · 목적지는 왼쪽 | Arrive · on the left | 到着 · 目的地は左側 |
| 40 | 남은 시간 | {분}분 · 오전 11:39 도착 | {분} min · Arrive 11:39 AM | {분}分 · 午前11:39 到着 |
| 41 | 지금 위치 밝기 | 지금 이곳 · 밝음/보통/어두움 | Here now · Bright/Fair/Dark | 現在地 · 明るい/普通/暗い |
| 42 | 안심 타이머 | 안심 타이머 23:40까지 | Safety timer until 23:40 | 安心タイマー 23:40まで |
| 43 | 버튼 | 손전등 / 화면 밝게 / 안내 종료 | Flashlight / Brighten / End | ライト / 画面を明るく / 案内終了 |
| 44 | 목록 제목 | 전체 안내 | All directions | 全体の案内 |
| 45 | 도착 화면 | 도착했어요 · 걸은 거리 · 걸음 · 걸린 시간 · 닫기 | You've arrived · Distance · Steps · Time · Close | 到着しました · 歩いた距離 · 歩数 · 所要時間 · 閉じる |
