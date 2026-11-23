import 'package:ansim_core/ansim_core.dart';

import 'safety_data.dart';

/// 내 주변(반경 [radiusM]) 안심 요약: 도로 칸 평균 안심지수 + 시설 수.
class AreaSafety {
  final int score;
  final int lights;
  final int cctvs;
  final int bells;
  final double radiusM;
  const AreaSafety(this.score, this.lights, this.cctvs, this.bells, this.radiusM);

  static AreaSafety? at(SafetyData data, GeoPoint p, {double radiusM = 300}) {
    // 30m 격자로 원 안의 도로 칸 안심점수 평균
    final dLat = 30 / metersPerDegLat, dLng = 30 / metersPerDegLng(p.lat);
    final k = (radiusM / 30).ceil();
    var sum = 0.0, n = 0;
    for (var i = -k; i <= k; i++) {
      for (var j = -k; j <= k; j++) {
        if (i * i + j * j > k * k) continue;
        final s = data.raster.scoreAt(p.lat + i * dLat, p.lng + j * dLng);
        if (s != null) {
          sum += s;
          n++;
        }
      }
    }
    if (n == 0) return null;
    final f = data.facilities;
    var l = 0, c = 0, b = 0;
    f.index.forEachCandidate(p.lat, p.lng, radiusM, (i) {
      if (haversineM(p.lat, p.lng, f.lat(i), f.lng(i)) > radiusM) return;
      switch (f.typeOf(i)) {
        case FacilityType.light:
          l += f.weights[i];
        case FacilityType.cctv:
          c += f.weights[i];
        case FacilityType.bell:
          b += f.weights[i];
      }
    });
    return AreaSafety((sum / n * 100).round(), l, c, b, radiusM);
  }
}
