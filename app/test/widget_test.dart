import 'package:ansim_core/ansim_core.dart';
import 'package:ansimdidi/controllers/theme_controller.dart';
import 'package:ansimdidi/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('밤 시간대 판정', () {
    expect(ThemeController.isNightHour(DateTime(2026, 11, 23, 22)), isTrue);
    expect(ThemeController.isNightHour(DateTime(2026, 11, 23, 3)), isTrue);
    expect(ThemeController.isNightHour(DateTime(2026, 11, 23, 13)), isFalse);
  });

  test('안심지수 등급 문구', () {
    expect(scoreLabel(70), '밝음');
    expect(scoreLabel(45), '보통');
    expect(scoreLabel(10), '어두움');
  });

  test('경로 진행률: 경로 위 중간 지점', () {
    const a = GeoPoint(35.15, 129.05), b = GeoPoint(35.15, 129.061);
    final mid = GeoPoint(35.15, (a.lng + b.lng) / 2);
    final p = progressOnPolyline([a, b], mid);
    expect(p.offRouteM, lessThan(1));
    expect(p.remainingM, closeTo(p.totalM / 2, 2));
  });
}
