import 'dart:math' as math;

/// 위도·경도 한 점 (WGS84).
class GeoPoint {
  final double lat;
  final double lng;
  const GeoPoint(this.lat, this.lng);

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'GeoPoint(${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)})';
}

/// 위도 1도의 길이(m). 부산 규모(수십 km)에서는 등장방형 근사로 충분하다.
const double metersPerDegLat = 111195.0;

double metersPerDegLng(double lat) => metersPerDegLat * math.cos(lat * math.pi / 180);

/// 두 점 사이 대권 거리(m).
double haversineM(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371008.8;
  const p = math.pi / 180;
  final dLat = (lat2 - lat1) * p;
  final dLng = (lng2 - lng1) * p;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * p) * math.cos(lat2 * p) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(a)));
}

double distanceM(GeoPoint a, GeoPoint b) => haversineM(a.lat, a.lng, b.lat, b.lng);

/// 점 p에서 선분 ab까지의 최단 거리(m). 짧은 거리용 평면 근사.
double pointSegmentDistanceM(
    double pLat, double pLng, double aLat, double aLng, double bLat, double bLng) {
  final mLng = metersPerDegLng(pLat);
  final ax = (aLng - pLng) * mLng, ay = (aLat - pLat) * metersPerDegLat;
  final bx = (bLng - pLng) * mLng, by = (bLat - pLat) * metersPerDegLat;
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  var t = len2 == 0 ? 0.0 : -(ax * dx + ay * dy) / len2;
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  final cx = ax + t * dx, cy = ay + t * dy;
  return math.sqrt(cx * cx + cy * cy);
}

double polylineLengthM(List<GeoPoint> pts) {
  var sum = 0.0;
  for (var i = 1; i < pts.length; i++) {
    sum += distanceM(pts[i - 1], pts[i]);
  }
  return sum;
}

/// 폴리라인을 일정 간격(m)으로 다시 샘플링한다. 양 끝점은 항상 포함.
/// 반환되는 각 샘플은 해당 샘플이 대표하는 구간 길이(weightM)를 함께 가진다.
List<PathSample> resamplePolyline(List<GeoPoint> pts, double stepM) {
  final out = <PathSample>[];
  if (pts.isEmpty) return out;
  if (pts.length == 1) return [PathSample(pts.first, 0)];
  var carry = 0.0; // 마지막 샘플 이후 진행한 거리
  out.add(PathSample(pts.first, 0));
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    final seg = distanceM(a, b);
    if (seg == 0) continue;
    var pos = stepM - carry; // 이 선분에서 다음 샘플 위치
    while (pos <= seg) {
      final t = pos / seg;
      out.add(PathSample(GeoPoint(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t), stepM));
      pos += stepM;
    }
    carry = seg - (pos - stepM);
  }
  if (carry > 0.01) {
    out.add(PathSample(pts.last, carry));
  } else {
    // 마지막 샘플이 끝점과 (부동소수 오차 수준으로) 겹치면 정확한 끝점으로 교체
    out[out.length - 1] = PathSample(pts.last, out.last.weightM);
  }
  return out;
}

/// 현재 위치를 경로 위에 투영한 결과(안내 중 남은 거리·이탈 판정용).
class PolylineProgress {
  /// 경로까지의 최단 거리(m). 크면 경로 이탈.
  final double offRouteM;

  /// 출발점부터 투영점까지 경로를 따라 간 거리(m).
  final double alongM;
  final double totalM;

  /// 투영점이 놓인 구간 번호(점 i → i+1). 구간 점수를 찾을 때 쓴다.
  final int segment;
  const PolylineProgress(this.offRouteM, this.alongM, this.totalM, [this.segment = 0]);

  double get remainingM => (totalM - alongM).clamp(0, totalM).toDouble();
}

PolylineProgress progressOnPolyline(List<GeoPoint> pts, GeoPoint p) {
  if (pts.length < 2) {
    final d = pts.isEmpty ? double.infinity : distanceM(pts.first, p);
    return PolylineProgress(d, 0, 0);
  }
  var best = double.infinity, bestAlong = 0.0, acc = 0.0;
  var bestSeg = 0;
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    final seg = distanceM(a, b);
    final d = pointSegmentDistanceM(p.lat, p.lng, a.lat, a.lng, b.lat, b.lng);
    if (d < best) {
      best = d;
      // 선분 위 투영 위치 = 피타고라스로 a에서의 거리 추정
      final da = distanceM(a, p);
      final t = seg == 0 ? 0.0 : (math.sqrt(math.max(0, da * da - d * d)) / seg).clamp(0.0, 1.0);
      bestAlong = acc + seg * t;
      bestSeg = i - 1;
    }
    acc += seg;
  }
  return PolylineProgress(best, bestAlong, acc, bestSeg);
}

class PathSample {
  final GeoPoint point;

  /// 직전 샘플에서 이 샘플까지의 길이(m). 길이 가중 평균에 사용.
  final double weightM;
  const PathSample(this.point, this.weightM);
}

class GeoBounds {
  final double minLat, minLng, maxLat, maxLng;
  const GeoBounds(this.minLat, this.minLng, this.maxLat, this.maxLng);

  factory GeoBounds.fromPoints(Iterable<GeoPoint> pts) {
    var minLat = 90.0, minLng = 180.0, maxLat = -90.0, maxLng = -180.0;
    for (final p in pts) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLng = math.min(minLng, p.lng);
      maxLng = math.max(maxLng, p.lng);
    }
    return GeoBounds(minLat, minLng, maxLat, maxLng);
  }

  bool contains(double lat, double lng) =>
      lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng;

  GeoBounds expandedBy(double meters) {
    final dLat = meters / metersPerDegLat;
    final dLng = meters / metersPerDegLng((minLat + maxLat) / 2);
    return GeoBounds(minLat - dLat, minLng - dLng, maxLat + dLat, maxLng + dLng);
  }

  GeoPoint get center => GeoPoint((minLat + maxLat) / 2, (minLng + maxLng) / 2);

  @override
  String toString() => 'GeoBounds($minLat,$minLng ~ $maxLat,$maxLng)';
}

/// 부산광역시 대략 범위. 이 밖의 좌표는 안심경로 계산 대상이 아니다.
const busanBounds = GeoBounds(34.85, 128.74, 35.45, 129.35);
