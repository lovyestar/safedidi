import 'package:ansim_core/ansim_core.dart';

import '../theme.dart';

/// 길 안내 화면 문구(한국어·영어·일본어). 안내 문장(회전·음성)은 ansim_core의 [GuidePhrases].
/// 안내 언어를 바꾸면 위 안내 카드·안내 목록·안내 중 시트·도착 화면이 함께 바뀐다.
class GuideText {
  final GuideLang lang;
  const GuideText._(this.lang);

  static const ko = GuideText._(GuideLang.ko);
  static const en = GuideText._(GuideLang.en);
  static const ja = GuideText._(GuideLang.ja);
  static GuideText of(GuideLang l) => switch (l) {
        GuideLang.ko => ko,
        GuideLang.en => en,
        GuideLang.ja => ja,
      };

  GuidePhrases get phrases => GuidePhrases.of(lang);

  String _t(String k, String e, String j) => switch (lang) {
        GuideLang.ko => k,
        GuideLang.en => e,
        GuideLang.ja => j,
      };

  // 위 안내 카드
  String get followRoute => _t('경로를 따라 이동하세요', 'Follow the route', 'ルートに沿って進んでください');
  String get thenLabel => _t('그다음', 'Then', 'その先');
  String get now => _t('곧', 'Now', 'まもなく');
  String get destFallback => _t('도착지', 'Destination', '目的地');

  // 안내 목록
  String get depart => _t('출발', 'Start', '出発');
  String departToward(String road) => _t('$road 방면', 'Toward $road', '$road方面');
  String arrive(String? side) => side == null
      ? _t('도착', 'Arrive', '到着')
      : _t('도착 · 목적지는 $side', 'Arrive · on the $side', '到着 · 目的地は$side');

  // 안내 중 시트
  String get locating => _t('위치 확인 중…', 'Finding your location…', '現在地を確認中…');
  String get minUnit => _t('분', ' min', '分');
  String eta(DateTime t) => _t('${_clockKo(t)} 도착', 'Arrive ${_clockEn(t)}', '${_clockJa(t)} 到着');
  String get hereNow => _t('지금 이곳', 'Here now', '現在地');
  String brightness(Brightness3 b) => switch (b) {
        Brightness3.bright => _t('밝음', 'Bright', '明るい'),
        Brightness3.normal => _t('보통', 'Fair', '普通'),
        Brightness3.dark => _t('어두움', 'Dark', '暗い'),
      };
  String timerUntil(DateTime t) {
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return _t('안심 타이머 $hm까지', 'Safety timer until $hm', '安心タイマー $hmまで');
  }

  String rerouted(int n) => _t('현위치에서 $n번 다시 찾음', 'Rerouted $n×', '$n回 再検索');
  String get torch => _t('손전등', 'Flashlight', 'ライト');
  String get brighten => _t('화면 밝게', 'Brighten', '画面を明るく');
  String get stop => _t('안내 종료', 'End', '案内終了');
  String get allSteps => _t('전체 안내', 'All directions', '全体の案内');

  // 도착 화면
  String get arrivedTitle => _t('도착했어요', "You've arrived", '到着しました');
  String get arrivedFallback => _t('오늘도 안전한 귀가였어요', 'Get home safe!', 'お疲れさまでした');
  String get walked => _t('걸은 거리', 'Distance', '歩いた距離');
  String get steps => _t('걸음', 'Steps', '歩数');
  String get took => _t('걸린 시간', 'Time', '所要時間');
  String minutes(int n) => _t('$n분', '$n min', '$n分');
  String get close => _t('닫기', 'Close', '閉じる');

  static String _h12(DateTime t) => '${t.hour % 12 == 0 ? 12 : t.hour % 12}:${t.minute.toString().padLeft(2, '0')}';
  static String _clockKo(DateTime t) => '${t.hour < 12 ? '오전' : '오후'} ${_h12(t)}';
  static String _clockEn(DateTime t) => '${_h12(t)} ${t.hour < 12 ? 'AM' : 'PM'}';
  static String _clockJa(DateTime t) => '${t.hour < 12 ? '午前' : '午後'}${_h12(t)}';
}
