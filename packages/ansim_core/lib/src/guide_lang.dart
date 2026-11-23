import 'guidance.dart';
import 'road_graph.dart';
import 'romanize.dart';

/// 길 안내 언어. 음성(TTS) 언어와 안내 화면 문구가 함께 바뀐다.
enum GuideLang {
  ko('ko-KR', '한국어'),
  en('en-US', 'English'),
  ja('ja-JP', '日本語');

  /// TTS 언어 코드
  final String ttsLocale;

  /// 언어 이름(그 언어로)
  final String nativeName;
  const GuideLang(this.ttsLocale, this.nativeName);

  static GuideLang parse(String? code) => values.firstWhere((l) => l.name == code, orElse: () => ko);
}

/// 경로 이름 종류(안내 시작 음성 등에 쓴다)
enum RouteKind { safe, shortest, tmap, general }

/// 언어별 길 안내 문장. 한국어는 네이버 지도 도보 안내 말투,
/// 영어·일본어는 각 나라 지도 앱의 도보 안내 말투를 따른다.
///
/// 영어·일본어에서 도로 이름은 로마자로 보여주고(Jungang-daero),
/// 일본어 음성은 로마자 도로 이름을 읽기 어려워 음성에서는 뺀다.
abstract class GuidePhrases {
  const GuidePhrases();

  static const ko = KoPhrases();
  static const en = EnPhrases();
  static const ja = JaPhrases();

  static GuidePhrases of(GuideLang lang) => switch (lang) {
        GuideLang.ko => ko,
        GuideLang.en => en,
        GuideLang.ja => ja,
      };

  GuideLang get lang;

  /// 안내 카드 큰 글씨(회전)
  String turnLabel(TurnKind t);

  /// 음성(회전)
  String turnSpeech(TurnKind t);
  String featureLabel(EdgeFeature f);
  String featureSpeech(EdgeFeature f);

  /// 목적지 방향 낱말: 왼쪽·오른쪽
  String? sideWord(int side);

  /// 안내 카드 큰 글씨. 예: "좌회전 후 횡단보도 건너기", "Turn left, then cross the crosswalk"
  String title(Maneuver m);

  /// 음성(앞에 "잠시 후"를 붙일 수 있는 형태)
  String speech(Maneuver m);

  /// 화면에 보일 도로 이름
  String road(String name) => name;

  /// 음성에 넣을 도로 이름(null이면 음성에서 뺀다)
  String? spokenRoad(String name) => road(name);

  /// 음성 거리: "536미터", "536 meters", "536メートル"
  String meters(double m);

  /// 약 50m 전 안내: "잠시 후 왼쪽 방향입니다"
  String soon(String speech, double distM);

  /// 바로 이어지는 안내를 붙인다: "왼쪽 방향입니다, 이어서 횡단보도를 건너세요"
  String chain(String first, String next);

  /// 도로를 벗어나 목적지로 들어가기 약 50m 전
  String arriveSoon(Maneuver arrive, double distM);

  /// 도착했을 때
  String arrived(int side);

  String routeName(RouteKind k);

  /// 안내 시작: 경로 요약 + 첫 안내
  String start({
    required RouteKind kind,
    required int minutes,
    required double distanceM,
    required int score,
    Maneuver? first,
    double? firstDistM,
    String? firstRoad,
    bool firstIsNear = false,
  });

  String rerouted();
  String timerDue();

  /// 50m 안팎 거리를 10m 단위로(음성용)
  static int round10(double m) => ((m / 10).round() * 10).clamp(10, 1 << 30);
}

// ── 한국어 ───────────────────────────────────────────────
class KoPhrases extends GuidePhrases {
  const KoPhrases();
  @override
  GuideLang get lang => GuideLang.ko;
  @override
  String turnLabel(TurnKind t) => t.label;
  @override
  String turnSpeech(TurnKind t) => t.speech;
  @override
  String featureLabel(EdgeFeature f) => switch (f) {
        EdgeFeature.crossing => '횡단보도 건너기',
        EdgeFeature.overpass => '육교 건너기',
        EdgeFeature.underpass => '지하도 이용',
        EdgeFeature.steps => '계단 이용',
        EdgeFeature.none => '',
      };
  @override
  String featureSpeech(EdgeFeature f) => switch (f) {
        EdgeFeature.crossing => '횡단보도를 건너세요',
        EdgeFeature.overpass => '육교를 건너세요',
        EdgeFeature.underpass => '지하도를 이용하세요',
        EdgeFeature.steps => '계단을 이용하세요',
        EdgeFeature.none => '',
      };
  @override
  String? sideWord(int side) => side < 0 ? '왼쪽' : (side > 0 ? '오른쪽' : null);
  @override
  String title(Maneuver m) {
    final side = sideWord(m.side);
    if (m.turn == TurnKind.arrive && side != null) return '목적지는 $side';
    if (m.feature == EdgeFeature.none) return turnLabel(m.turn);
    if (m.turn.isTurn) return '${turnLabel(m.turn)} 후 ${featureLabel(m.feature)}';
    return featureLabel(m.feature);
  }

  @override
  String speech(Maneuver m) {
    final side = sideWord(m.side);
    if (m.turn == TurnKind.arrive && side != null) return '목적지는 $side에 있습니다';
    if (m.feature == EdgeFeature.none) return turnSpeech(m.turn);
    if (m.turn.isTurn) return '${turnSpeech(m.turn).replaceAll('입니다', '')}, ${featureSpeech(m.feature)}';
    return featureSpeech(m.feature);
  }

  @override
  String meters(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(1)}킬로미터' : '${m.round()}미터';
  @override
  String soon(String speech, double distM) => '잠시 후 $speech';
  @override
  String chain(String first, String next) => '$first, 이어서 $next';
  @override
  String arriveSoon(Maneuver arrive, double distM) {
    final side = sideWord(arrive.side);
    return side == null ? '잠시 후 목적지입니다.' : '잠시 후 목적지입니다. ${speech(arrive)}';
  }

  @override
  String arrived(int side) {
    final s = sideWord(side);
    return s == null ? '목적지에 도착했어요. 오늘도 안전한 귀가였어요.' : '목적지에 도착했어요. 목적지는 $s에 있어요.';
  }

  @override
  String routeName(RouteKind k) => switch (k) {
        RouteKind.safe => '안심 경로',
        RouteKind.shortest => '최단 경로',
        RouteKind.tmap => 'TMAP 경로',
        RouteKind.general => '일반 경로',
      };

  @override
  String start({
    required RouteKind kind,
    required int minutes,
    required double distanceM,
    required int score,
    Maneuver? first,
    double? firstDistM,
    String? firstRoad,
    bool firstIsNear = false,
  }) {
    final buf = StringBuffer('${routeName(kind)} 안내를 시작합니다. 약 $minutes분, '
        '${meters(distanceM)} 거리이고 안심지수는 $score점입니다. ');
    if (first != null && firstDistM != null) {
      if (firstIsNear) {
        buf.write(soon(speech(first), firstDistM));
      } else {
        buf.write('${firstRoad == null ? '' : '$firstRoad${eulReul(firstRoad)} 따라 '}${meters(firstDistM)} 직진하세요.');
      }
    }
    return buf.toString();
  }

  @override
  String rerouted() => '경로를 벗어나 현재 위치에서 안심 경로를 다시 찾았어요.';
  @override
  String timerDue() => '예상 도착 시간이 지났어요. 괜찮으세요? 화면을 확인해 주세요.';

  /// 받침에 맞는 목적격 조사(을/를)
  static String eulReul(String w) {
    final c = w.codeUnitAt(w.length - 1);
    if (c < 0xAC00 || c > 0xD7A3) return '을(를)';
    return (c - 0xAC00) % 28 == 0 ? '를' : '을';
  }
}

// ── English ──────────────────────────────────────────────
class EnPhrases extends GuidePhrases {
  const EnPhrases();
  @override
  GuideLang get lang => GuideLang.en;
  @override
  String turnLabel(TurnKind t) => switch (t) {
        TurnKind.depart => 'Start',
        TurnKind.straight => 'Go straight',
        TurnKind.slightLeft => 'Slight left',
        TurnKind.left => 'Turn left',
        TurnKind.sharpLeft => 'Sharp left',
        TurnKind.uTurn => 'U-turn',
        TurnKind.slightRight => 'Slight right',
        TurnKind.right => 'Turn right',
        TurnKind.sharpRight => 'Sharp right',
        TurnKind.arrive => 'Arrive',
      };
  @override
  String turnSpeech(TurnKind t) => switch (t) {
        TurnKind.depart => 'Start walking',
        TurnKind.straight => 'Go straight',
        TurnKind.slightLeft => 'Keep slightly left',
        TurnKind.left => 'Turn left',
        TurnKind.sharpLeft => 'Turn sharply left',
        TurnKind.uTurn => 'Turn around',
        TurnKind.slightRight => 'Keep slightly right',
        TurnKind.right => 'Turn right',
        TurnKind.sharpRight => 'Turn sharply right',
        TurnKind.arrive => 'You have reached your destination',
      };
  @override
  String featureLabel(EdgeFeature f) => switch (f) {
        EdgeFeature.crossing => 'Cross the crosswalk',
        EdgeFeature.overpass => 'Cross the footbridge',
        EdgeFeature.underpass => 'Take the underpass',
        EdgeFeature.steps => 'Take the stairs',
        EdgeFeature.none => '',
      };
  @override
  String featureSpeech(EdgeFeature f) => featureLabel(f);
  @override
  String? sideWord(int side) => side < 0 ? 'left' : (side > 0 ? 'right' : null);
  @override
  String title(Maneuver m) {
    final side = sideWord(m.side);
    if (m.turn == TurnKind.arrive && side != null) return 'Destination on the $side';
    if (m.feature == EdgeFeature.none) return turnLabel(m.turn);
    if (m.turn.isTurn) return '${turnLabel(m.turn)}, then ${_lower(featureLabel(m.feature))}';
    return featureLabel(m.feature);
  }

  @override
  String speech(Maneuver m) {
    final side = sideWord(m.side);
    if (m.turn == TurnKind.arrive && side != null) return 'Your destination is on the $side';
    if (m.feature == EdgeFeature.none) return turnSpeech(m.turn);
    if (m.turn.isTurn) return '${turnSpeech(m.turn)}, then ${_lower(featureSpeech(m.feature))}';
    return featureSpeech(m.feature);
  }

  @override
  String road(String name) => romanizeRoad(name);
  @override
  String meters(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} kilometers' : '${m.round()} meters';
  @override
  String soon(String speech, double distM) => 'In ${GuidePhrases.round10(distM)} meters, ${_lower(speech)}';
  @override
  String chain(String first, String next) => '$first, then ${_lower(next)}';
  @override
  String arriveSoon(Maneuver arrive, double distM) {
    final head = 'In ${GuidePhrases.round10(distM)} meters, you will reach your destination.';
    final side = sideWord(arrive.side);
    return side == null ? head : '$head It is on the $side.';
  }

  @override
  String arrived(int side) {
    final s = sideWord(side);
    return s == null ? 'You have arrived. Get home safe!' : 'You have arrived. Your destination is on the $s.';
  }

  @override
  String routeName(RouteKind k) => switch (k) {
        RouteKind.safe => 'safe route',
        RouteKind.shortest => 'shortest route',
        RouteKind.tmap => 'TMAP route',
        RouteKind.general => 'regular route',
      };

  @override
  String start({
    required RouteKind kind,
    required int minutes,
    required double distanceM,
    required int score,
    Maneuver? first,
    double? firstDistM,
    String? firstRoad,
    bool firstIsNear = false,
  }) {
    final buf = StringBuffer('Starting ${routeName(kind)} guidance. About $minutes minutes, '
        '${meters(distanceM)}, safety score $score. ');
    if (first != null && firstDistM != null) {
      if (firstIsNear) {
        buf.write('${soon(speech(first), firstDistM)}.');
      } else {
        final r = firstRoad == null ? null : spokenRoad(firstRoad);
        buf.write('Go straight for ${meters(firstDistM)}${r == null ? '' : ' on $r'}.');
      }
    }
    return buf.toString();
  }

  @override
  String rerouted() => 'You left the route. Found a new safe route from your current location.';
  @override
  String timerDue() => "You're past your expected arrival time. Are you okay? Please check your screen.";

  static String _lower(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
}

// ── 日本語 ───────────────────────────────────────────────
class JaPhrases extends GuidePhrases {
  const JaPhrases();
  @override
  GuideLang get lang => GuideLang.ja;
  @override
  String turnLabel(TurnKind t) => switch (t) {
        TurnKind.depart => '出発',
        TurnKind.straight => '直進',
        TurnKind.slightLeft => '斜め左',
        TurnKind.left => '左折',
        TurnKind.sharpLeft => '大きく左',
        TurnKind.uTurn => 'Uターン',
        TurnKind.slightRight => '斜め右',
        TurnKind.right => '右折',
        TurnKind.sharpRight => '大きく右',
        TurnKind.arrive => '目的地に到着',
      };

  /// 「〜方向です」の「です」を除いた部分(つなげて使う)
  String _dir(TurnKind t) => switch (t) {
        TurnKind.depart => '出発',
        TurnKind.straight => '直進',
        TurnKind.slightLeft => '斜め左方向',
        TurnKind.left => '左方向',
        TurnKind.sharpLeft => '大きく左方向',
        TurnKind.uTurn => 'Uターン',
        TurnKind.slightRight => '斜め右方向',
        TurnKind.right => '右方向',
        TurnKind.sharpRight => '大きく右方向',
        TurnKind.arrive => '目的地',
      };
  @override
  String turnSpeech(TurnKind t) => switch (t) {
        TurnKind.depart => '出発します',
        TurnKind.uTurn => 'Uターンしてください',
        _ => '${_dir(t)}です',
      };
  @override
  String featureLabel(EdgeFeature f) => switch (f) {
        EdgeFeature.crossing => '横断歩道を渡る',
        EdgeFeature.overpass => '歩道橋を渡る',
        EdgeFeature.underpass => '地下道を通る',
        EdgeFeature.steps => '階段を利用',
        EdgeFeature.none => '',
      };
  @override
  String featureSpeech(EdgeFeature f) => switch (f) {
        EdgeFeature.crossing => '横断歩道を渡ってください',
        EdgeFeature.overpass => '歩道橋を渡ってください',
        EdgeFeature.underpass => '地下道を通ってください',
        EdgeFeature.steps => '階段を利用してください',
        EdgeFeature.none => '',
      };
  @override
  String? sideWord(int side) => side < 0 ? '左側' : (side > 0 ? '右側' : null);
  @override
  String title(Maneuver m) {
    final side = sideWord(m.side);
    if (m.turn == TurnKind.arrive && side != null) return '目的地は$side';
    if (m.feature == EdgeFeature.none) return turnLabel(m.turn);
    if (m.turn.isTurn) return '${turnLabel(m.turn)}して${featureLabel(m.feature)}';
    return featureLabel(m.feature);
  }

  @override
  String speech(Maneuver m) {
    final side = sideWord(m.side);
    if (m.turn == TurnKind.arrive && side != null) return '目的地は$sideです';
    if (m.feature == EdgeFeature.none) return turnSpeech(m.turn);
    if (m.turn.isTurn) return '${_dir(m.turn)}、${featureSpeech(m.feature)}';
    return featureSpeech(m.feature);
  }

  @override
  String road(String name) => romanizeRoad(name);

  /// 日本語の音声はローマ字の道路名をうまく読めないので省く
  @override
  String? spokenRoad(String name) => null;
  @override
  String meters(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(1)}キロメートル' : '${m.round()}メートル';
  @override
  String soon(String speech, double distM) => '${GuidePhrases.round10(distM)}メートル先、$speech';
  @override
  String chain(String first, String next) => '$first。その先、$next';
  @override
  String arriveSoon(Maneuver arrive, double distM) {
    final head = '${GuidePhrases.round10(distM)}メートル先、目的地です。';
    final side = sideWord(arrive.side);
    return side == null ? head : '$head目的地は$sideです。';
  }

  @override
  String arrived(int side) {
    final s = sideWord(side);
    return s == null ? '目的地に到着しました。お疲れさまでした。' : '目的地に到着しました。目的地は$sです。';
  }

  @override
  String routeName(RouteKind k) => switch (k) {
        RouteKind.safe => '安心ルート',
        RouteKind.shortest => '最短ルート',
        RouteKind.tmap => 'TMAPルート',
        RouteKind.general => '通常ルート',
      };

  @override
  String start({
    required RouteKind kind,
    required int minutes,
    required double distanceM,
    required int score,
    Maneuver? first,
    double? firstDistM,
    String? firstRoad,
    bool firstIsNear = false,
  }) {
    final buf = StringBuffer('${routeName(kind)}の案内を開始します。約$minutes分、'
        '${meters(distanceM)}、安心指数は$score点です。');
    if (first != null && firstDistM != null) {
      buf.write(firstIsNear ? '${soon(speech(first), firstDistM)}。' : '${meters(firstDistM)}直進してください。');
    }
    return buf.toString();
  }

  @override
  String rerouted() => 'ルートを外れたため、現在地から安心ルートを再検索しました。';
  @override
  String timerDue() => '到着予定時刻を過ぎました。大丈夫ですか?画面を確認してください。';
}
