import 'package:flutter/material.dart';

/// 안심디디 색상. 주색 두 가지: 가로등 노랑(브랜드·주요 버튼) + 안심 초록(안심 경로·켜짐·좋음).
/// 바탕은 초록빛이 살짝 도는 무채색이라 두 색이 튀지 않고 어울린다.
class AppColors {
  // 야간: 초록빛 먹색
  static const night = Color(0xFF0C1411);
  static const nightSurface = Color(0xFF141F1A);
  static const nightSurfaceHigh = Color(0xFF1D2B25);
  static const nightLine = Color(0xFF283830);

  // 주간
  static const day = Color(0xFFF2F5F0);
  static const daySurface = Colors.white;
  static const dayFill = Color(0xFFEEF2EB);
  static const dayLine = Color(0xFFE1E7DD);

  /// 가로등 노랑: 브랜드·주요 버튼(안내 시작 등)
  static const lamp = Color(0xFFFFC21A);
  static const lampDeep = Color(0xFFE5A000);
  static const onLamp = Color(0xFF2A1F00);

  /// 안심 초록: 안심 경로·켜짐·좋아진 값
  static const leaf = Color(0xFF1DB869);
  static const leafDeep = Color(0xFF0E9A54);
  static const onLeaf = Colors.white;

  /// 일반(최단) 경로
  static const plain = Color(0xFF97A29B);

  /// 위험·SOS
  static const danger = Color(0xFFF2434F);

  static const cctv = Color(0xFF6E7CF5);
  static const bell = Color(0xFFFF7A59);
  static const good = leaf;
  static const police = Color(0xFF2F6BFF);
  static const store = Color(0xFF14A89C);

  static const textSub = Color(0xFF86918A);
}

/// 앱 테마: 색·글꼴·바탕만 정한다. 버튼·시트·알림 같은 부품 모양은 ui/kit.dart에서 직접 그린다
/// (머티리얼 기본 부품 모양을 쓰지 않음).
ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final surface = dark ? AppColors.nightSurface : AppColors.daySurface;
  final line = dark ? AppColors.nightLine : AppColors.dayLine;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.leaf,
    brightness: b,
    primary: dark ? AppColors.leaf : AppColors.leafDeep,
    onPrimary: dark ? const Color(0xFF04150C) : AppColors.onLeaf,
    secondary: AppColors.lamp,
    onSecondary: AppColors.onLamp,
    surface: surface,
    surfaceContainerHighest: dark ? AppColors.nightSurfaceHigh : AppColors.dayFill,
    outlineVariant: line,
    error: AppColors.danger,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b, fontFamily: 'Pretendard');
  final ink = dark ? const Color(0xFFE8EEE9) : const Color(0xFF18201B);
  return base.copyWith(
    // 머티리얼 물결·눌림 색을 끈다(누름 효과는 ui/kit.dart의 Pressable이 직접 그린다)
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    scaffoldBackgroundColor: dark ? AppColors.night : AppColors.day,
    textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    iconTheme: IconThemeData(color: ink),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.leafDeep,
      selectionColor: Color(0x551DB869),
      selectionHandleColor: AppColors.leafDeep,
    ),
  );
}

/// 안심점수(0~1) → 색. 어두움(빨강) → 보통(노랑) → 밝음(초록).
Color scoreColor(double v) {
  const stops = [
    (0.0, Color(0xFFF2434F)),
    (0.25, Color(0xFFFF9F1C)),
    (0.4, Color(0xFFFFC21A)),
    (0.6, Color(0xFF1DB869)),
  ];
  if (v <= stops.first.$1) return stops.first.$2;
  for (var i = 1; i < stops.length; i++) {
    if (v <= stops[i].$1) {
      final t = (v - stops[i - 1].$1) / (stops[i].$1 - stops[i - 1].$1);
      return Color.lerp(stops[i - 1].$2, stops[i].$2, t)!;
    }
  }
  return stops.last.$2;
}

/// 글자용 안심점수 색: 밝은 화면에서는 노랑이 흐려 보여 조금 어둡게.
Color scoreInk(double v, Brightness b) =>
    b == Brightness.dark ? scoreColor(v) : Color.lerp(scoreColor(v), const Color(0xFF000000), 0.25)!;

/// 경로 색칠용 3단계(밝음·보통·어두움).
enum Brightness3 { bright, normal, dark }

Brightness3 brightnessOf(double score) =>
    score >= 0.45 ? Brightness3.bright : (score >= 0.25 ? Brightness3.normal : Brightness3.dark);

/// 밝음=초록, 보통=노랑, 어두움=빨강(신호등처럼 한눈에)
Color brightnessColor(Brightness3 b) => switch (b) {
      Brightness3.bright => AppColors.leaf,
      Brightness3.normal => AppColors.lamp,
      Brightness3.dark => AppColors.danger,
    };

String brightnessLabel(Brightness3 b) => switch (b) {
      Brightness3.bright => '밝음',
      Brightness3.normal => '보통',
      Brightness3.dark => '어두움',
    };

/// 글자용 3단계 색: 밝은 화면에서는 노랑이 흐려 보여 진한 노랑으로.
Color brightnessInk(Brightness3 b, Brightness ui) => switch (b) {
      Brightness3.bright => ui == Brightness.dark ? AppColors.leaf : AppColors.leafDeep,
      Brightness3.normal => ui == Brightness.dark ? AppColors.lamp : AppColors.lampDeep,
      Brightness3.dark => AppColors.danger,
    };

/// 안심지수(0~100) 등급 문구.
String scoreLabel(int score) {
  if (score >= 60) return '밝음';
  if (score >= 40) return '보통';
  if (score >= 25) return '조금 어두움';
  return '어두움';
}

String fmtDist(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(1)}km' : '${m.round()}m';
