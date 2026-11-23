import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// 안심디디 로고: 밤하늘 아래 가로등(노랑)이 초록 길을 비추는 모양.
/// 앱 안 로고와 안드로이드 런처 아이콘(test/tool/make_icons_test.dart로 PNG 생성)이 같은 그림을 쓴다.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: const CustomPaint(painter: AppLogoPainter()));
}

const _skyTop = Color(0xFF143A28);
const _skyBottom = Color(0xFF07130D);
const _lamp = Color(0xFFFFC21A);
const _leaf = Color(0xFF1DB869);
const _pole = Color(0xFFE6EEE8);

/// [background]: 둥근 사각 밤하늘을 그릴지. [contentScale]: 그림을 가운데 기준으로 줄이는 비율
/// (적응형 아이콘 전경은 안전 영역 안에 들어오도록 0.7 정도로 줄인다).
class AppLogoPainter extends CustomPainter {
  final bool background;
  final double contentScale;
  final double corner;
  const AppLogoPainter({this.background = true, this.contentScale = 1, this.corner = 0.23});

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    if (background) paintSky(canvas, s, corner: corner);
    canvas.save();
    canvas.translate(w / 2, w / 2);
    canvas.scale(contentScale);
    canvas.translate(-w / 2, -w / 2);
    _paintScene(canvas, w);
    canvas.restore();
  }

  /// 밤하늘 바탕(둥근 사각, corner=0이면 꽉 찬 사각)
  static void paintSky(Canvas canvas, Size s, {double corner = 0.23}) {
    final w = s.width;
    final rect = Offset.zero & s;
    final sky = Paint()
      ..shader = ui.Gradient.linear(Offset(0, 0), Offset(0, w), const [_skyTop, _skyBottom]);
    if (corner > 0) {
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(w * corner)), sky);
    } else {
      canvas.drawRect(rect, sky);
    }
    // 작은 별 몇 개
    final star = Paint()..color = const Color(0x99FFFFFF);
    for (final (x, y, r) in const [(0.22, 0.20, 0.010), (0.30, 0.34, 0.007), (0.80, 0.16, 0.008), (0.86, 0.36, 0.006), (0.16, 0.46, 0.006)]) {
      canvas.drawCircle(Offset(w * x, w * y), w * r, star);
    }
  }

  void _paintScene(Canvas canvas, double w) {
    Offset o(double x, double y) => Offset(w * x, w * y);

    // 길: 가운데 선(S자 베지어)을 따라 아래는 넓고 멀수록 좁아지는 초록 길
    Offset center(double t) {
      const p0 = (0.42, 0.90), p1 = (0.33, 0.76), p2 = (0.53, 0.63), p3 = (0.47, 0.50);
      final u = 1 - t;
      final x = u * u * u * p0.$1 + 3 * u * u * t * p1.$1 + 3 * u * t * t * p2.$1 + t * t * t * p3.$1;
      final y = u * u * u * p0.$2 + 3 * u * u * t * p1.$2 + 3 * u * t * t * p2.$2 + t * t * t * p3.$2;
      return Offset(x, y);
    }

    double half(double t) => 0.205 * math.pow(1 - t, 1.35) + 0.008;
    const n = 40;
    final left = <Offset>[], right = <Offset>[];
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      final c = center(t);
      // 원근감: 폭은 가로 방향으로만 줄인다(굽은 곳에서 길이 접히지 않게)
      final h = half(t);
      left.add(o(c.dx - h, c.dy));
      right.add(o(c.dx + h, c.dy));
    }
    final road = ui.Path()..addPolygon([...left, ...right.reversed], true);
    canvas.drawPath(
      road,
      Paint()..shader = ui.Gradient.linear(o(0, 0.49), o(0, 0.90), const [Color(0xFFB6EC8A), _leaf]),
    );
    // 길 가운데 점선(멀수록 짧고 가늘게)
    final dash = Paint()
      ..color = const Color(0xD9FFFFFF)
      ..strokeCap = StrokeCap.round;
    for (final (t0, t1, sw) in const [(0.06, 0.16, 0.020), (0.30, 0.38, 0.015), (0.52, 0.58, 0.011), (0.70, 0.74, 0.008)]) {
      final a = center(t0), b = center(t1);
      canvas.drawLine(o(a.dx, a.dy), o(b.dx, b.dy), dash..strokeWidth = w * sw);
    }

    // 불빛: 등에서 길로 퍼지는 원뿔 + 등 주변 번짐
    final cone = ui.Path()
      ..moveTo(w * 0.42, w * 0.285)
      ..lineTo(w * 0.53, w * 0.285)
      ..lineTo(w * 0.66, w * 0.80)
      ..lineTo(w * 0.24, w * 0.80)
      ..close();
    canvas.drawPath(
      cone,
      Paint()..shader = ui.Gradient.linear(o(0, 0.28), o(0, 0.80), [_lamp.withValues(alpha: 0.42), _lamp.withValues(alpha: 0)]),
    );
    canvas.drawCircle(
      o(0.475, 0.27),
      w * 0.17,
      Paint()..shader = ui.Gradient.radial(o(0.475, 0.27), w * 0.17, [_lamp.withValues(alpha: 0.55), _lamp.withValues(alpha: 0)]),
    );

    // 가로등 기둥과 팔
    final pole = Paint()
      ..color = _pole
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.042
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      ui.Path()
        ..moveTo(w * 0.70, w * 0.84)
        ..lineTo(w * 0.70, w * 0.27)
        ..quadraticBezierTo(w * 0.70, w * 0.19, w * 0.61, w * 0.19)
        ..lineTo(w * 0.53, w * 0.19),
      pole,
    );
    // 기둥 받침
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: o(0.70, 0.845), width: w * 0.10, height: w * 0.035), Radius.circular(w * 0.015)),
      Paint()..color = _pole,
    );
    // 등갓 + 전구
    final shade = ui.Path()
      ..moveTo(w * 0.40, w * 0.275)
      ..quadraticBezierTo(w * 0.42, w * 0.19, w * 0.475, w * 0.185)
      ..quadraticBezierTo(w * 0.53, w * 0.19, w * 0.55, w * 0.275)
      ..close();
    canvas.drawPath(shade, Paint()..color = _pole);
    canvas.drawOval(Rect.fromCenter(center: o(0.475, 0.278), width: w * 0.13, height: w * 0.045), Paint()..color = _lamp);
  }

  @override
  bool shouldRepaint(covariant AppLogoPainter old) =>
      old.background != background || old.contentScale != contentScale || old.corner != corner;
}

/// 적응형 아이콘 바탕(밤하늘만, 꽉 찬 사각)
class AppLogoBackgroundPainter extends CustomPainter {
  const AppLogoBackgroundPainter();

  @override
  void paint(Canvas canvas, Size s) => AppLogoPainter.paintSky(canvas, s, corner: 0);

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
