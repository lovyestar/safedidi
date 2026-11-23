// 런처 아이콘 PNG 생성기. 평소 테스트에서는 건너뛰고, 아래처럼 실행할 때만 만든다.
//   MAKE_ICONS=1 flutter test test/tool/make_icons_test.dart
// 출력: android 런처 아이콘(구형 둥근 사각 + 적응형 전경/바탕), docs/app_icon.png(512px)
// ICON_PREVIEW=경로 를 주면 그 경로에 512px 미리보기만 저장한다.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ansimdidi/ui/logo.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _png(CustomPainter painter, int px, String path) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  painter.paint(canvas, Size(px.toDouble(), px.toDouble()));
  final img = await rec.endRecording().toImage(px, px);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(data!.buffer.asUint8List());
}

void main() {
  final env = Platform.environment;
  final preview = env['ICON_PREVIEW'];
  final make = env['MAKE_ICONS'] == '1';

  testWidgets('아이콘 미리보기', (tester) async {
    await tester.runAsync(() => _png(const AppLogoPainter(), 512, preview!));
  }, skip: preview == null);

  testWidgets('런처 아이콘 생성', (tester) async {
    await tester.runAsync(() async {
      const res = 'android/app/src/main/res';
      const legacy = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
      for (final e in legacy.entries) {
        await _png(const AppLogoPainter(), e.value, '$res/mipmap-${e.key}/ic_launcher.png');
        // 적응형 아이콘: 108dp 캔버스, 바깥 18dp는 잘릴 수 있어 그림을 줄여 넣는다
        final adaptive = e.value * 108 ~/ 48;
        await _png(const AppLogoPainter(background: false, contentScale: 0.66), adaptive,
            '$res/mipmap-${e.key}/ic_launcher_foreground.png');
        await _png(const AppLogoBackgroundPainter(), adaptive, '$res/mipmap-${e.key}/ic_launcher_background.png');
      }
      await _png(const AppLogoPainter(), 512, '../docs/app_icon.png');
    });
  }, skip: !make);
}
