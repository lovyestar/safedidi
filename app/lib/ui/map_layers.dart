import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ansim_core/ansim_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/safe_places.dart';
import '../theme.dart';
import 'app_icons.dart';

LatLng toL(GeoPoint p) => LatLng(p.lat, p.lng);

/// OSM 기본 타일 서버. 앱 식별(User-Agent)은 TileLayer의 userAgentPackageName으로 보낸다.
const osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const appPackageName = 'com.ansimdidi';

/// 주간 지도: OSM 기본 색이 화려해 데모처럼 보이므로 채도를 45%로 낮추고 살짝 밝게 덮는다.
/// 그래야 경로·도로 밝기 색이 지도 위에서 또렷하다(네이버·카카오 지도의 차분한 바탕처럼).
const dayTileFilter = ColorFilter.matrix(<double>[
  0.4989, 0.3462, 0.0349, 0, 29.5, //
  0.1029, 0.7422, 0.0349, 0, 31.5, //
  0.1029, 0.3462, 0.4309, 0, 29.5, //
  0, 0, 0, 1, 0, //
]);

/// 야간 지도: OSM 타일을 색 반전 + 색조 180° 회전(원래 색감 유지) + 밝기 0.8.
/// 타일마다가 아니라 타일 레이어 전체에 한 번만 적용해야 빠르다.
const nightTileFilter = ColorFilter.matrix(<double>[
  0.459, -1.144, -0.115, 0, 199, //
  -0.341, -0.344, -0.115, 0, 199, //
  -0.341, -1.144, 0.685, 0, 199, //
  0, 0, 0, 1, 0, //
]);

// ── 밝기 지도 타일 ────────────────────────────────────────
/// 내장 래스터(heat.bin)에서 바로 그리는 '밝기 지도' 타일. 지도 이동 중 계산이 없다.
class HeatTileProvider extends TileProvider {
  final SafetyRaster raster;
  HeatTileProvider(this.raster);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _HeatTile(raster, coordinates.z, coordinates.x, coordinates.y);
}

/// 점수(0~250) → RGBA 색표(1회 계산)
final Uint32List _palette = () {
  final p = Uint32List(251);
  for (var v = 0; v <= 250; v++) {
    final s = v / 250.0;
    final c = scoreColor(s);
    final a = (s < 0.25 ? 0.6 : 0.42) * 255;
    // RGBA 바이트 순서 → little-endian uint32
    p[v] = (c.r * 255).round() | ((c.g * 255).round() << 8) | ((c.b * 255).round() << 16) | (a.round() << 24);
  }
  return p;
}();

@immutable
class _HeatTile extends ImageProvider<_HeatTile> {
  static const size = 64;
  final SafetyRaster raster;
  final int z, x, y;
  const _HeatTile(this.raster, this.z, this.x, this.y);

  @override
  Future<_HeatTile> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_HeatTile key, ImageDecoderCallback decode) => OneFrameImageStreamCompleter(_render());

  Future<ImageInfo> _render() async {
    final px = Uint32List(size * size);
    final n = (1 << z).toDouble();
    for (var py = 0; py < size; py++) {
      final yy = (y + (py + 0.5) / size) / n;
      final lat = math.atan(_sinh(math.pi * (1 - 2 * yy))) * 180 / math.pi;
      for (var pxi = 0; pxi < size; pxi++) {
        final lng = (x + (pxi + 0.5) / size) / n * 360 - 180;
        final v = raster.rawAt(lat, lng);
        if (v != SafetyRaster.noRoad) px[py * size + pxi] = _palette[v];
      }
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(px.buffer.asUint8List(), size, size, ui.PixelFormat.rgba8888, done.complete);
    return ImageInfo(image: await done.future);
  }

  static double _sinh(double v) => (math.exp(v) - math.exp(-v)) / 2;

  @override
  bool operator ==(Object other) =>
      other is _HeatTile && identical(other.raster, raster) && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(identityHashCode(raster), z, x, y);
}

// ── 도로 밝기 레이어(교통정보 레이어처럼 도로 선에 색) ────────────
/// 보행 도로를 안심점수로 색칠한 타일. 지도 앱의 교통정보 레이어처럼 도로 위에만 그린다.
class RoadSafetyTileProvider extends TileProvider {
  final RoadGraph graph;
  final Float32List edgeScores;
  RoadSafetyTileProvider(this.graph, this.edgeScores);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _RoadTile(this, coordinates.z, coordinates.x, coordinates.y);
}

@immutable
class _RoadTile extends ImageProvider<_RoadTile> {
  final RoadSafetyTileProvider src;
  final int z, x, y;
  const _RoadTile(this.src, this.z, this.x, this.y);

  @override
  Future<_RoadTile> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_RoadTile key, ImageDecoderCallback decode) => OneFrameImageStreamCompleter(_render());

  Future<ImageInfo> _render() async {
    // 멀리 볼 때(z≤15)는 256px, 가까이 볼 때만 512px로 그려 픽셀 수를 줄인다.
    final size = z >= 16 ? 512 : 256;
    final g = src.graph;
    final n = (1 << z).toDouble();
    double tileLng(double tx) => tx / n * 360 - 180;
    double tileLat(double ty) => math.atan(_HeatTile._sinh(math.pi * (1 - 2 * ty / n))) * 180 / math.pi;
    final north = tileLat(y.toDouble()), south = tileLat(y + 1.0);
    final west = tileLng(x.toDouble()), east = tileLng(x + 1.0);
    final padLat = (north - south) * 0.05, padLng = (east - west) * 0.05;
    final minLat = south - padLat, maxLat = north + padLat, minLng = west - padLng, maxLng = east + padLng;

    double px(double lng) => ((lng + 180) / 360 * n - x) * size;
    double py(double lat) {
      final r = lat * math.pi / 180;
      return ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n - y) * size;
    }

    // 색별 선분 좌표(x1,y1,x2,y2…)를 모아 한 번에 그린다(drawRawPoints).
    final pts = {for (final b in Brightness3.values) b: <double>[]};
    final flags = g.edgeFlags, targets = g.targets, offsets = g.offsets, scores = src.edgeScores;
    final far = z <= 14; // 멀리서 볼 땐 보도·계단·보행자거리 생략
    g.nodeIndex.forEachInBox(minLat, minLng, maxLat, maxLng, (u) {
      final uLat = g.lat(u), uLng = g.lng(u);
      double? ux, uy;
      for (var e = offsets[u]; e < offsets[u + 1]; e++) {
        final cls = RoadFlags.roadClass(flags[e]);
        if (cls == RoadClass.trail || cls == RoadClass.service) continue; // 산길·진입로 생략
        if (far && (cls == RoadClass.footway || cls == RoadClass.steps || cls == RoadClass.pedestrian)) continue;
        final v = targets[e];
        final vLat = g.lat(v), vLng = g.lng(v);
        // 같은 도로가 양방향으로 저장돼 있으니 한 번만: 반대쪽 노드도 범위 안이면 번호가 작은 쪽에서 그린다
        final vIn = vLat >= minLat && vLat <= maxLat && vLng >= minLng && vLng <= maxLng;
        if (vIn && v < u) continue;
        ux ??= px(uLng);
        uy ??= py(uLat);
        pts[brightnessOf(scores[e])]!.addAll([ux, uy, px(vLng), py(vLat)]);
      }
    });
    final width = switch (z) { <= 14 => 1.4, 15 => 2.2, 16 => 4.6, 17 => 6.0, _ => 8.0 };
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    for (final b in [Brightness3.bright, Brightness3.normal, Brightness3.dark]) {
      final list = pts[b]!;
      if (list.isEmpty) continue;
      canvas.drawRawPoints(
        ui.PointMode.lines,
        Float32List.fromList(list),
        Paint()
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..color = brightnessColor(b).withValues(alpha: b == Brightness3.dark ? 0.8 : 0.68),
      );
    }
    final img = await rec.endRecording().toImage(size, size);
    return ImageInfo(image: img);
  }

  @override
  bool operator ==(Object other) =>
      other is _RoadTile && identical(other.src, src) && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(identityHashCode(src), z, x, y);
}

// ── 경로 구간 색칠 ────────────────────────────────────────
/// 경로를 밝음(초록)·보통(노랑)·어두움(빨강) 구간으로 나눈 폴리라인들.
List<Polyline> coloredRoute(RouteMetrics m, {double width = 8}) {
  // 실제 도로 점(꼭짓점)을 그대로 따라가며, 구간 점수(지도 '도로 밝기'와 같은 도로 조각 점수)로 색칠한다.
  // 10m 샘플 점을 이으면 모퉁이마다 대각선으로 지름길을 그려 도로에서 벗어나 보였다.
  final pts = m.points, sc = m.segmentScores;
  if (pts.length < 2 || sc.length != pts.length - 1) return const [];
  final out = <Polyline>[];
  List<LatLng>? seg;
  Brightness3? cur;
  void flush() {
    if (seg != null && seg!.length >= 2) out.add(Polyline(points: seg!, strokeWidth: width, color: brightnessColor(cur!)));
    seg = null;
  }

  for (var i = 0; i < sc.length; i++) {
    if (m.isConnector(i)) {
      flush();
      continue;
    }
    final b = brightnessOf(sc[i]);
    if (seg == null || b != cur) {
      flush();
      seg = [toL(pts[i])];
      cur = b;
    }
    seg!.add(toL(pts[i + 1]));
  }
  flush();
  return out;
}

/// 경로의 도로 부분(연결선 제외) 점들
List<List<LatLng>> _roadParts(RouteMetrics m) {
  final pts = m.points;
  final parts = <List<LatLng>>[];
  List<LatLng>? cur;
  for (var i = 0; i < pts.length - 1; i++) {
    if (m.isConnector(i)) {
      if (cur != null && cur.length >= 2) parts.add(cur);
      cur = null;
      continue;
    }
    cur ??= [toL(pts[i])];
    cur.add(toL(pts[i + 1]));
  }
  if (cur != null && cur.length >= 2) parts.add(cur);
  return parts;
}

/// 경로 밑에 깔리는 테두리(연결선 제외)
List<Polyline> routeCasing(RouteMetrics m, {double width = 8, Color color = const Color(0xFF14261C)}) => [
      for (final part in _roadParts(m)) Polyline(points: part, strokeWidth: width + 4, color: color),
    ];

/// 출발점·도착점을 도로에 잇는 짧은 선: 도로 밖이라 점선(지도 앱처럼)
List<Polyline> routeConnectors(RouteMetrics m, {Color color = const Color(0xFF8A928C)}) => [
      for (var i = 0; i < m.points.length - 1; i++)
        if (m.isConnector(i))
          Polyline(
            points: [toL(m.points[i]), toL(m.points[i + 1])],
            strokeWidth: 4,
            color: color,
            pattern: const StrokePattern.dotted(),
          ),
    ];

/// 경로 진행 방향 화살표(지도 앱처럼 [everyM]마다). 마커가 지도와 함께 돌아 방향이 유지된다.
List<Marker> routeArrows(RouteMetrics m, {double everyM = 110, Color color = const Color(0xFF0E1F15)}) {
  final pts = m.points;
  if (pts.length < 2) return const [];
  final out = <Marker>[];
  var next = everyM * 0.6, acc = 0.0;
  for (var i = 1; i < pts.length; i++) {
    if (m.isConnector(i - 1)) continue;
    final a = pts[i - 1], b = pts[i];
    final seg = distanceM(a, b);
    if (seg == 0) continue;
    // 진북 기준 방위각(라디안)
    final dy = (b.lat - a.lat) * metersPerDegLat, dx = (b.lng - a.lng) * metersPerDegLng(a.lat);
    final bearing = math.atan2(dx, dy);
    while (next <= acc + seg) {
      final t = (next - acc) / seg;
      out.add(Marker(
        point: LatLng(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t),
        width: 14,
        height: 14,
        child: Transform.rotate(
          angle: bearing,
          child: CustomPaint(painter: _ChevronPainter(color)),
        ),
      ));
      next += everyM;
    }
    acc += seg;
  }
  return out;
}

// ── 핀·점 ─────────────────────────────────────────────────
IconData safeKindIcon(SafePlaceKind k) => switch (k) {
      SafePlaceKind.police => Ic.police,
      SafePlaceKind.store => Ic.store,
      SafePlaceKind.pharmacy => Ic.pharmacy,
      SafePlaceKind.emergency => Ic.emergency,
    };

/// 경로 진행 방향 꺾쇠(위쪽을 가리킴)
class _ChevronPainter extends CustomPainter {
  final Color color;
  _ChevronPainter(this.color);

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawPath(
      ui.Path()
        ..moveTo(s.width * 0.2, s.height * 0.68)
        ..lineTo(s.width * 0.5, s.height * 0.36)
        ..lineTo(s.width * 0.8, s.height * 0.68),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.width * 0.18
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ChevronPainter old) => old.color != color;
}

Color safeKindColor(SafePlaceKind k) => switch (k) {
      SafePlaceKind.police => AppColors.police,
      SafePlaceKind.store => AppColors.store,
      SafePlaceKind.pharmacy => const Color(0xFF2FA84F),
      SafePlaceKind.emergency => AppColors.danger,
    };

Color facilityColor(FacilityType t) => switch (t) {
      FacilityType.light => AppColors.lamp,
      FacilityType.cctv => AppColors.cctv,
      FacilityType.bell => AppColors.bell,
    };

/// 출발·도착 핀(지도 앱처럼 위가 둥근 물방울 모양).
class PlacePin extends StatelessWidget {
  final Color color;
  final Color fg;
  final String label;
  const PlacePin({super.key, required this.color, required this.label, this.fg = Colors.white});

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(blurRadius: 4, color: Color(0x55000000), offset: Offset(0, 1))],
          ),
          child: Text(label, style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ),
        CustomPaint(size: const Size(10, 6), painter: _TrianglePainter(color)),
      ]);
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  _TrianglePainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}

/// 경로 주변 안전 장소(편의점·지구대) 핀.
class SafePlacePin extends StatelessWidget {
  final SafePlaceKind kind;
  const SafePlacePin(this.kind, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: safeKindColor(kind),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(blurRadius: 3, color: Color(0x55000000))],
        ),
        child: Icon(safeKindIcon(kind), size: 14, color: Colors.white),
      );
}

class _BeamPainter extends CustomPainter {
  const _BeamPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    final r = s.width / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawPath(
      ui.Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(rect, -math.pi / 2 - 0.55, 1.1, false)
        ..close(),
      Paint()
        ..shader = ui.Gradient.radial(c, r, [const Color(0x993D8BFF), const Color(0x003D8BFF)]),
    );
  }

  @override
  bool shouldRepaint(covariant _BeamPainter old) => false;
}

/// 장소 카드로 보고 있는 곳(노란 물방울 핀)
class PreviewPin extends StatelessWidget {
  const PreviewPin({super.key});

  @override
  Widget build(BuildContext context) => const CustomPaint(size: Size(34, 44), painter: _DropPainter(AppColors.lamp, AppColors.onLamp));
}

class _DropPainter extends CustomPainter {
  final Color color;
  final Color dot;
  const _DropPainter(this.color, this.dot);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height, r = w / 2;
    final path = ui.Path()
      ..moveTo(w / 2, h)
      ..cubicTo(w * 0.18, h * 0.62, 0, h * 0.5, 0, r)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
      ..cubicTo(w, h * 0.5, w * 0.82, h * 0.62, w / 2, h)
      ..close();
    canvas.drawShadow(path, const Color(0x66000000), 3, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawCircle(Offset(w / 2, r), r * 0.38, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(covariant _DropPainter old) => old.color != color || old.dot != dot;
}

/// 내 위치(파란 점 + 진행 방향).
class MyLocationDot extends StatelessWidget {
  final double? heading;
  const MyLocationDot({super.key, this.heading});

  @override
  Widget build(BuildContext context) => Stack(alignment: Alignment.center, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: const Color(0xFF3D8BFF).withValues(alpha: 0.16), shape: BoxShape.circle),
        ),
        // 바라보는 방향: 부채꼴 빛(지도 앱의 방향 표시처럼)
        if (heading != null)
          Transform.rotate(
            angle: heading! * math.pi / 180,
            child: const SizedBox(width: 44, height: 44, child: CustomPaint(painter: _BeamPainter())),
          ),
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: const Color(0xFF3D8BFF),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(blurRadius: 3, color: Color(0x44000000))],
          ),
        ),
      ]);
}
