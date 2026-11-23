import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ansim_core/ansim_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'app_icons.dart';
import 'guide_text.dart';
import 'kit.dart';

/// 회전 안내 화면 부품: 네이버 지도 도보 안내처럼 위쪽 안내 카드 + 단계별 목록.

/// 안내 지점 아이콘: 회전은 직접 그린 굵은 화살표(네이버 지도 안내처럼), 횡단보도는 얼룩말 무늬,
/// 계단·육교·지하도·도착은 아이콘.
class ManeuverIcon extends StatelessWidget {
  final Maneuver m;
  final double size;
  final Color color;
  const ManeuverIcon(this.m, {super.key, this.size = 24, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = m.turn;
    // 회전 + 횡단보도면 회전 화살표가 우선(어느 쪽으로 가는지가 더 중요)
    if (!t.isTurn && t != TurnKind.arrive && t != TurnKind.depart) {
      switch (m.feature) {
        case EdgeFeature.crossing:
          return SizedBox(width: size, height: size, child: CustomPaint(painter: _ZebraPainter(color)));
        case EdgeFeature.steps || EdgeFeature.overpass:
          return Icon(Ic.stairs, size: size * 0.92, color: color);
        case EdgeFeature.underpass:
          return Icon(Ic.subway, size: size * 0.9, color: color);
        case EdgeFeature.none:
          break;
      }
    }
    if (t == TurnKind.arrive) return Icon(Ic.flag, size: size * 0.9, color: color);
    if (t == TurnKind.depart) return Icon(Ic.walk, size: size * 0.9, color: color);
    return SizedBox(width: size, height: size, child: CustomPaint(painter: TurnArrowPainter(t, color)));
  }
}

/// 회전 화살표: 아래에서 올라와 꺾이는 굵은 선 + 화살촉
class TurnArrowPainter extends CustomPainter {
  final TurnKind kind;
  final Color color;
  TurnArrowPainter(this.kind, this.color);

  static double _angle(TurnKind k) => switch (k) {
        TurnKind.slightLeft => -45,
        TurnKind.left => -90,
        TurnKind.sharpLeft => -135,
        TurnKind.slightRight => 45,
        TurnKind.right => 90,
        TurnKind.sharpRight => 135,
        _ => 0,
      };

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.15
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;

    void head(Offset tip, double dirRad) {
      // dirRad: 화살 방향(위=0, 시계 방향 +)
      final hl = w * 0.30, hw = w * 0.24;
      final dx = math.sin(dirRad), dy = -math.cos(dirRad);
      final back = Offset(tip.dx - dx * hl, tip.dy - dy * hl);
      final px = -dy, py = dx;
      canvas.drawPath(
        ui.Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(back.dx + px * hw, back.dy + py * hw)
          ..lineTo(back.dx - px * hw, back.dy - py * hw)
          ..close(),
        fill,
      );
    }

    if (kind == TurnKind.uTurn) {
      final r = w * 0.19;
      final cx = w * 0.45, top = w * 0.40;
      final path = ui.Path()
        ..moveTo(cx + r, w * 0.92)
        ..lineTo(cx + r, top)
        ..arcToPoint(Offset(cx - r, top), radius: Radius.circular(r), clockwise: false)
        ..lineTo(cx - r, w * 0.56);
      canvas.drawPath(path, stroke);
      head(Offset(cx - r, w * 0.84), math.pi);
      return;
    }
    final deg = _angle(kind);
    final a = deg * math.pi / 180;
    final dx = math.sin(a), dy = -math.cos(a);
    // 꺾이는 정도에 따라 꺾는 높이를 바꾸고, 그림이 가운데 오도록 줄기를 반대쪽으로 민다
    final sharp = deg.abs() > 100, slight = deg.abs() < 60;
    final pivotY = w * (sharp ? 0.34 : (slight ? 0.56 : 0.50));
    final cx = w * 0.5 - dx * w * (sharp ? 0.26 : (slight ? 0.10 : 0.17));
    final pivot = Offset(cx, pivotY);
    final len = w * (slight ? 0.42 : (sharp ? 0.48 : 0.40));
    final tip = Offset(pivot.dx + dx * len, pivot.dy + dy * len);
    final headLen = w * 0.28;
    final shaftEnd = Offset(tip.dx - dx * headLen * 0.8, tip.dy - dy * headLen * 0.8);
    // 모퉁이는 둥글게(곡선 반지름 r)
    final r = w * 0.12;
    final path = ui.Path()
      ..moveTo(cx, w * 0.94)
      ..lineTo(cx, pivotY + r)
      ..quadraticBezierTo(pivot.dx, pivot.dy, pivot.dx + dx * r, pivot.dy + dy * r)
      ..lineTo(shaftEnd.dx, shaftEnd.dy);
    canvas.drawPath(path, stroke);
    head(tip, a);
  }

  @override
  bool shouldRepaint(covariant TurnArrowPainter old) => old.kind != kind || old.color != color;
}

class _ZebraPainter extends CustomPainter {
  final Color color;
  _ZebraPainter(this.color);

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = color;
    final w = s.width * 0.16, gap = s.width * 0.08;
    var x = s.width * 0.08;
    for (var i = 0; i < 4; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, s.height * 0.14, w, s.height * 0.72), Radius.circular(w * 0.3)),
        p,
      );
      x += w + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _ZebraPainter old) => old.color != color;
}

/// 안내 거리 표시: 10m 단위, 아주 가까우면 '곧'
String guideDist(double m, [GuideText t = GuideText.ko]) {
  if (m < 8) return t.now;
  if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)}km';
  return '${((m / 10).round() * 10).clamp(10, 990)}m';
}

/// 안내 중 위쪽 카드: [아이콘·남은 거리] 안내 문구 / 도로 이름, 아래 줄에 '그다음' 안내.
class TurnCard extends StatelessWidget {
  final Maneuver? next;
  final double? distM;
  final Maneuver? then;
  final String destName;
  final GuideLang lang;
  const TurnCard(
      {super.key, required this.next, required this.distM, required this.then, required this.destName, this.lang = GuideLang.ko});

  @override
  Widget build(BuildContext context) {
    final m = next;
    final t = GuideText.of(lang), ph = t.phrases;
    final title = m == null ? t.followRoute : ph.title(m);
    final sub = m == null ? null : (m.turn == TurnKind.arrive ? destName : (m.road == null ? null : ph.road(m.road!)));
    final showThen = m != null && then != null && then!.atM - m.atM <= 150;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.leafDeep,
        borderRadius: BorderRadius.circular(22),
        boxShadow: Pal.of(context).float,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
          child: Row(children: [
            Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
                child: m == null
                    ? const Icon(Ic.navigate, size: 32, color: Colors.white)
                    : ManeuverIcon(m, size: 38, color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(distM == null ? '' : guideDist(distM!, t),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
            ]),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, height: 1.25, fontWeight: FontWeight.w700, color: Colors.white)),
                if (sub != null) ...[
                  const SizedBox(height: 3),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Color(0xCCFFFFFF))),
                ],
              ]),
            ),
          ]),
        ),
        if (showThen)
          Container(
            width: double.infinity,
            color: const Color(0x26000000),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            child: Row(children: [
              Text(t.thenLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xB3FFFFFF))),
              const SizedBox(width: 8),
              ManeuverIcon(then!, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Expanded(
                child: Text(ph.title(then!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// 단계별 안내 한 줄: 아이콘 · 안내 문구(도로 이름) · 앞 안내에서 거리
class ManeuverTile extends StatelessWidget {
  final Maneuver m;
  final double? gapM;
  final bool passed;
  final bool current;
  final String? destName;
  final GuideLang lang;
  const ManeuverTile(
      {super.key, required this.m, this.gapM, this.passed = false, this.current = false, this.destName, this.lang = GuideLang.ko});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final fg = passed ? AppColors.textSub : (current ? AppColors.leafDeep : null);
    final t = GuideText.of(lang), ph = t.phrases;
    final road = m.road == null ? null : ph.road(m.road!);
    final title = switch (m.turn) {
      TurnKind.depart => t.depart,
      TurnKind.arrive => t.arrive(ph.sideWord(m.side)),
      _ => ph.title(m),
    };
    final sub = switch (m.turn) {
      TurnKind.depart => road == null ? null : t.departToward(road),
      TurnKind.arrive => destName,
      _ => road,
    };
    return Opacity(
      opacity: passed ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: current ? AppColors.leaf.withValues(alpha: 0.16) : p.fill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: ManeuverIcon(m, size: 20, color: fg ?? p.text),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: fg)),
              if (sub != null)
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textSub, fontWeight: FontWeight.w500)),
            ]),
          ),
          if (gapM != null && gapM! >= 1)
            Text(fmtDist(gapM!), style: const TextStyle(fontSize: 12, color: AppColors.textSub, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

/// 안내 목록 전체(앞 안내에서 몇 m 뒤인지 함께)
List<Widget> maneuverTiles(List<Maneuver> ms, {int currentIndex = -1, String? destName, GuideLang lang = GuideLang.ko}) => [
      for (var i = 0; i < ms.length; i++)
        ManeuverTile(
          m: ms[i],
          gapM: i == 0 ? null : ms[i].atM - ms[i - 1].atM,
          passed: currentIndex >= 0 && i < currentIndex,
          current: i == currentIndex,
          destName: destName,
          lang: lang,
        ),
    ];
