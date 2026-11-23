import 'dart:async';

import 'package:flutter/material.dart';

enum ThemeChoice { auto, dark, light }

/// 화면 테마: 다크/라이트 직접 선택, 또는 시간에 맞춰 자동(18시~7시 다크).
/// 선택은 [onChanged]로 저장한다(설정 화면에서 바꾼다).
class ThemeController extends ChangeNotifier {
  ThemeChoice choice;
  void Function(ThemeChoice)? onChanged;
  Timer? _tick;

  ThemeController({this.choice = ThemeChoice.auto, this.onChanged}) {
    // 자동 모드에서 해가 지면 바로 바뀌도록 1분마다 확인
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (choice == ThemeChoice.auto) notifyListeners();
    });
  }

  static bool isNightHour([DateTime? now]) {
    final h = (now ?? DateTime.now()).hour;
    return h >= 18 || h < 7;
  }

  bool get auto => choice == ThemeChoice.auto;

  /// 지금 실제로 다크 테마인지(자동이면 시간 기준)
  bool get isDark => switch (choice) {
        ThemeChoice.dark => true,
        ThemeChoice.light => false,
        ThemeChoice.auto => isNightHour(),
      };

  ThemeMode get mode => isDark ? ThemeMode.dark : ThemeMode.light;

  String get label => switch (choice) {
        ThemeChoice.auto => '자동 (지금 ${isDark ? '다크' : '라이트'})',
        ThemeChoice.dark => '다크',
        ThemeChoice.light => '라이트',
      };

  /// 저장된 선택을 앱 시작 때 적용(다시 저장하지 않음)
  void restore(ThemeChoice c) {
    choice = c;
    notifyListeners();
  }

  void set(ThemeChoice c) {
    if (c == choice) return;
    choice = c;
    onChanged?.call(c);
    notifyListeners();
  }

  /// '다크 모드' 스위치: 켜면 다크, 끄면 라이트(자동은 해제)
  void setDark(bool dark) => set(dark ? ThemeChoice.dark : ThemeChoice.light);

  /// '시간에 맞춰 자동' 스위치: 끄면 지금 보이는 테마로 고정
  void setAuto(bool on) => set(on ? ThemeChoice.auto : (isDark ? ThemeChoice.dark : ThemeChoice.light));

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}
