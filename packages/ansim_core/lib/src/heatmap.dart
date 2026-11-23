import 'dart:math' as math;
import 'dart:typed_data';

import 'facilities.dart';
import 'geo.dart';
import 'road_graph.dart';
import 'safety_model.dart';

/// 화면 범위의 안전시설 밀집도 격자(히트맵).
/// values[row * cols + col], row 0 = 북쪽(화면 위). 값이 음수면 도로가 없는 칸(투명).
class SafetyHeatmap {
  final GeoBounds bounds;
  final int cols;
  final int rows;
  final Float32List values;
  const SafetyHeatmap(this.bounds, this.cols, this.rows, this.values);

  static SafetyHeatmap compute(
    FacilityStore store,
    GeoBounds bounds, {
    RoadGraph? roadMask,
    SafetyModel model = const SafetyModel(),
    int cols = 40,
    int rows = 60,
  }) {
    final values = Float32List(cols * rows);
    final cellLat = (bounds.maxLat - bounds.minLat) / rows;
    final cellLng = (bounds.maxLng - bounds.minLng) / cols;
    final halfDiagM = 0.5 *
        math.sqrt(math.pow(cellLat * metersPerDegLat, 2) +
            math.pow(cellLng * metersPerDegLng(bounds.center.lat), 2));
    final norm = model.wLight + model.wCctv;
    for (var r = 0; r < rows; r++) {
      final lat = bounds.maxLat - (r + 0.5) * cellLat;
      for (var c = 0; c < cols; c++) {
        final lng = bounds.minLng + (c + 0.5) * cellLng;
        if (roadMask != null && roadMask.nearestNode(lat, lng, maxM: math.max(25, halfDiagM)) < 0) {
          values[r * cols + c] = -1;
          continue;
        }
        final lv = model.levelsAt(store, lat, lng);
        final v = (model.wLight * lv.light + model.wCctv * lv.cctv + model.wBell * lv.bell) / norm;
        values[r * cols + c] = v > 1 ? 1 : v;
      }
    }
    return SafetyHeatmap(bounds, cols, rows, values);
  }
}

/// 부산 전역 안심점수 래스터(전처리에서 한 번 계산해 앱에 내장).
/// 앱은 지도를 움직일 때 계산 없이 값만 읽어 '밝기 지도' 타일을 그린다.
///
/// 값: 0~250 = 안심점수(0~1)×250, 255 = 도로 없음(투명). row 0 = 남쪽.
/// 바이너리(little-endian, 헤더 48바이트):
///   u32 magic 'ADHT', u16 version(1), u16 0, u32 rows, u32 cols,
///   f64 minLat, f64 minLng, f64 cellLat, f64 cellLng, u8 values[rows*cols]
class SafetyRaster {
  static const int magic = 0x54484441; // 'ADHT'
  static const int version = 1;
  static const int noRoad = 255;

  final double minLat, minLng, cellLat, cellLng;
  final int rows, cols;
  final Uint8List values;

  const SafetyRaster(this.minLat, this.minLng, this.cellLat, this.cellLng, this.rows, this.cols, this.values);

  /// (lat,lng)의 원시 값. 범위 밖이거나 도로가 없으면 255.
  int rawAt(double lat, double lng) {
    final r = ((lat - minLat) / cellLat).floor();
    final c = ((lng - minLng) / cellLng).floor();
    if (r < 0 || r >= rows || c < 0 || c >= cols) return noRoad;
    return values[r * cols + c];
  }

  /// 안심점수(0~1). 도로가 없으면 null.
  double? scoreAt(double lat, double lng) {
    final v = rawAt(lat, lng);
    return v == noRoad ? null : v / 250.0;
  }

  /// 도로 조각을 래스터에 그려 넣고, 도로가 지나는 칸마다 안심점수를 계산한다.
  static SafetyRaster build(RoadGraph g, FacilityStore f,
      {SafetyModel model = const SafetyModel(), double cellM = 30}) {
    var minLat = 90.0, minLng = 180.0, maxLat = -90.0, maxLng = -180.0;
    for (var i = 0; i < g.nodeCount; i++) {
      final la = g.lat(i), lo = g.lng(i);
      if (la < minLat) minLat = la;
      if (la > maxLat) maxLat = la;
      if (lo < minLng) minLng = lo;
      if (lo > maxLng) maxLng = lo;
    }
    final cellLat = cellM / metersPerDegLat;
    final cellLng = cellM / metersPerDegLng((minLat + maxLat) / 2);
    minLat -= cellLat;
    minLng -= cellLng;
    final rows = ((maxLat - minLat) / cellLat).ceil() + 2;
    final cols = ((maxLng - minLng) / cellLng).ceil() + 2;
    // 칸마다 지나가는 도로 중 조명 추정치가 가장 높은 도로 등급을 기억
    final flags = Int16List(rows * cols)..fillRange(0, rows * cols, -1);
    final step = cellM / 2;
    for (var u = 0; u < g.nodeCount; u++) {
      final uLat = g.lat(u), uLng = g.lng(u);
      for (var e = g.offsets[u]; e < g.offsets[u + 1]; e++) {
        final v = g.targets[e];
        if (v < u) continue; // 무방향 엣지는 한 번만
        final n = (g.lengths[e] / step).ceil().clamp(1, 10000);
        final fl = g.edgeFlags[e];
        for (var k = 0; k <= n; k++) {
          final t = k / n;
          final la = uLat + (g.lat(v) - uLat) * t, lo = uLng + (g.lng(v) - uLng) * t;
          final r = ((la - minLat) / cellLat).floor(), c = ((lo - minLng) / cellLng).floor();
          if (r < 0 || r >= rows || c < 0 || c >= cols) continue;
          final idx = r * cols + c;
          final prev = flags[idx];
          if (prev < 0 || model.lightPrior(fl) > model.lightPrior(prev)) flags[idx] = fl;
        }
      }
    }
    final values = Uint8List(rows * cols)..fillRange(0, rows * cols, noRoad);
    for (var r = 0; r < rows; r++) {
      final la = minLat + (r + 0.5) * cellLat;
      for (var c = 0; c < cols; c++) {
        final idx = r * cols + c;
        final fl = flags[idx];
        if (fl < 0) continue;
        final lv = model.levelsAt(f, la, minLng + (c + 0.5) * cellLng);
        values[idx] = (model.score(lv.light, lv.cctv, lv.bell, fl) * 250).round().clamp(0, 250);
      }
    }
    return SafetyRaster(minLat, minLng, cellLat, cellLng, rows, cols, values);
  }

  Uint8List toBytes() {
    final bd = ByteData(48 + values.length);
    bd.setUint32(0, magic, Endian.little);
    bd.setUint16(4, version, Endian.little);
    bd.setUint32(8, rows, Endian.little);
    bd.setUint32(12, cols, Endian.little);
    bd.setFloat64(16, minLat, Endian.little);
    bd.setFloat64(24, minLng, Endian.little);
    bd.setFloat64(32, cellLat, Endian.little);
    bd.setFloat64(40, cellLng, Endian.little);
    final out = bd.buffer.asUint8List();
    out.setAll(48, values);
    return out;
  }

  factory SafetyRaster.fromBytes(ByteData bd) {
    if (bd.getUint32(0, Endian.little) != magic) throw const FormatException('heat.bin 형식이 아닙니다');
    final ver = bd.getUint16(4, Endian.little);
    if (ver != version) throw FormatException('지원하지 않는 heat.bin 버전: $ver');
    final rows = bd.getUint32(8, Endian.little), cols = bd.getUint32(12, Endian.little);
    final values = Uint8List(rows * cols)
      ..setAll(0, bd.buffer.asUint8List(bd.offsetInBytes + 48, rows * cols));
    return SafetyRaster(
      bd.getFloat64(16, Endian.little),
      bd.getFloat64(24, Endian.little),
      bd.getFloat64(32, Endian.little),
      bd.getFloat64(40, Endian.little),
      rows,
      cols,
      values,
    );
  }
}
