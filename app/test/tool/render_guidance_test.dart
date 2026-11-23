// 안내 화면 부품을 에뮬레이터 없이 그림으로 확인(평소엔 건너뜀).
//   UI_SHOT=경로.png flutter test test/tool/render_guidance_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ansim_core/ansim_core.dart';
import 'package:ansimdidi/theme.dart';
import 'package:ansimdidi/ui/guidance_widgets.dart';
import 'package:ansimdidi/ui/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _font(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await l.load();
}

void main() {
  final out = Platform.environment['UI_SHOT'];
  testWidgets('안내 부품 그림', (tester) async {
    await tester.runAsync(() async {
      await _font('Pretendard', [for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/Pretendard-$w.otf']);
      await _font('PhosphorBold', ['assets/fonts/Phosphor-Bold.ttf']);
      await _font('PhosphorFill', ['assets/fonts/Phosphor-Fill.ttf']);
    });
    const p = GeoPoint(35.15, 129.05);
    const ms = [
      Maneuver(turn: TurnKind.depart, atM: 0, point: p, road: '서전로'),
      Maneuver(turn: TurnKind.left, feature: EdgeFeature.crossing, atM: 120, point: p, road: '서면로'),
      Maneuver(turn: TurnKind.straight, feature: EdgeFeature.crossing, atM: 140, point: p),
      Maneuver(turn: TurnKind.slightRight, atM: 380, point: p, road: '중앙대로'),
      Maneuver(turn: TurnKind.sharpLeft, atM: 520, point: p),
      Maneuver(turn: TurnKind.uTurn, atM: 600, point: p),
      Maneuver(turn: TurnKind.straight, feature: EdgeFeature.steps, atM: 640, point: p),
      Maneuver(turn: TurnKind.arrive, atM: 700, point: p),
    ];
    final key = GlobalKey();
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 2.7;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(
        key: key,
        child: Scaffold(
          body: ListView(padding: const EdgeInsets.all(12), children: [
            TurnCard(next: ms[1], distM: 46, then: ms[2], destName: '부산역'),
            const SizedBox(height: 12),
            TurnCard(next: ms[7], distM: 30, then: null, destName: '부산역'),
            const SizedBox(height: 12),
            Row(children: [
              for (final m in ms.skip(1))
                Expanded(child: Center(child: ManeuverIcon(m, size: 34, color: AppColors.leafDeep))),
            ]),
            const SizedBox(height: 8),
            ...maneuverTiles(ms, currentIndex: 3, destName: '부산역'),
            const SizedBox(height: 8),
            const AppButton('안심 경로로 안내 시작', icon: IconData(0xe2d2, fontFamily: 'PhosphorFill'), onTap: _noop),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 2.7);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File(out!).writeAsBytesSync(data!.buffer.asUint8List());
    });
  }, skip: out == null);
}

void _noop() {}
