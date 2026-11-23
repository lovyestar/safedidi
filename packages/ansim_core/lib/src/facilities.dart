import 'dart:typed_data';

import 'geo.dart';
import 'grid_index.dart';

/// 안전시설 종류. 바이너리 포맷의 값과 순서가 같아야 한다.
enum FacilityType {
  light('가로등·보안등'),
  cctv('CCTV'),
  bell('비상벨');

  final String label;
  const FacilityType(this.label);
}

/// 안전시설 점 데이터(Structure of Arrays) + 격자 인덱스.
///
/// 바이너리 포맷(little-endian):
///   u32 magic 'ADFC', u16 version(1), u16 reserved, u32 count,
///   i32 latE6[count], i32 lngE6[count], u8 type[count], u8 weight[count]
class FacilityStore {
  static const int magic = 0x43464441; // 'ADFC'
  static const int version = 1;

  final Int32List latE6;
  final Int32List lngE6;
  final Uint8List types;

  /// 한 지점에 묶인 시설 수(보안등 설치개수, CCTV 카메라 대수 등). 1~255.
  final Uint8List weights;
  late final GridIndex index = GridIndex.build(
    count: length,
    latOf: lat,
    lngOf: lng,
    cellSizeM: 50,
  );

  FacilityStore(this.latE6, this.lngE6, this.types, this.weights)
      : assert(latE6.length == lngE6.length &&
            latE6.length == types.length &&
            latE6.length == weights.length);

  int get length => latE6.length;
  double lat(int i) => latE6[i] / 1e6;
  double lng(int i) => lngE6[i] / 1e6;
  FacilityType typeOf(int i) => FacilityType.values[types[i]];

  int countOf(FacilityType t) {
    var n = 0;
    for (var i = 0; i < length; i++) {
      if (types[i] == t.index) n += weights[i];
    }
    return n;
  }

  /// 범위 안의 시설 인덱스 목록.
  List<int> inBounds(GeoBounds b, {FacilityType? type, int limit = 1 << 30}) {
    final out = <int>[];
    index.forEachInBox(b.minLat, b.minLng, b.maxLat, b.maxLng, (i) {
      if (out.length >= limit) return;
      if (type != null && types[i] != type.index) return;
      final la = lat(i), lo = lng(i);
      if (b.contains(la, lo)) out.add(i);
    });
    return out;
  }

  /// 경로 폴리라인 주변(종류별 반경)에 있는 시설을 중복 없이 센다.
  FacilityTally tallyAlong(List<GeoPoint> path,
      {double lightRadiusM = 20, double cctvRadiusM = 30, double bellRadiusM = 30}) {
    final seen = <int>{};
    final maxR = [lightRadiusM, cctvRadiusM, bellRadiusM].reduce((a, b) => a > b ? a : b);
    double radiusFor(int t) => t == 0 ? lightRadiusM : (t == 1 ? cctvRadiusM : bellRadiusM);
    for (var s = 1; s < path.length; s++) {
      final a = path[s - 1], b = path[s];
      final box = GeoBounds.fromPoints([a, b]).expandedBy(maxR);
      index.forEachInBox(box.minLat, box.minLng, box.maxLat, box.maxLng, (i) {
        if (seen.contains(i)) return;
        final d = pointSegmentDistanceM(lat(i), lng(i), a.lat, a.lng, b.lat, b.lng);
        if (d <= radiusFor(types[i])) seen.add(i);
      });
    }
    if (path.length == 1) {
      final p = path.first;
      index.forEachCandidate(p.lat, p.lng, maxR, (i) {
        if (haversineM(lat(i), lng(i), p.lat, p.lng) <= radiusFor(types[i])) seen.add(i);
      });
    }
    var lights = 0, cctvs = 0, bells = 0;
    for (final i in seen) {
      switch (types[i]) {
        case 0:
          lights += weights[i];
        case 1:
          cctvs += weights[i];
        default:
          bells += weights[i];
      }
    }
    return FacilityTally(lights, cctvs, bells, seen.toList());
  }

  Uint8List toBytes() {
    final n = length;
    final bd = ByteData(16 + n * 10);
    bd.setUint32(0, magic, Endian.little);
    bd.setUint16(4, version, Endian.little);
    bd.setUint16(6, 0, Endian.little);
    bd.setUint32(8, n, Endian.little);
    var o = 16;
    for (var i = 0; i < n; i++, o += 4) {
      bd.setInt32(o, latE6[i], Endian.little);
    }
    for (var i = 0; i < n; i++, o += 4) {
      bd.setInt32(o, lngE6[i], Endian.little);
    }
    for (var i = 0; i < n; i++, o++) {
      bd.setUint8(o, types[i]);
    }
    for (var i = 0; i < n; i++, o++) {
      bd.setUint8(o, weights[i]);
    }
    return bd.buffer.asUint8List();
  }

  factory FacilityStore.fromBytes(ByteData bd) {
    if (bd.getUint32(0, Endian.little) != magic) {
      throw const FormatException('facilities.bin 형식이 아닙니다');
    }
    final ver = bd.getUint16(4, Endian.little);
    if (ver != version) throw FormatException('지원하지 않는 facilities.bin 버전: $ver');
    final n = bd.getUint32(8, Endian.little);
    final lat = Int32List(n), lng = Int32List(n);
    final types = Uint8List(n), weights = Uint8List(n);
    var o = 16;
    for (var i = 0; i < n; i++, o += 4) {
      lat[i] = bd.getInt32(o, Endian.little);
    }
    for (var i = 0; i < n; i++, o += 4) {
      lng[i] = bd.getInt32(o, Endian.little);
    }
    for (var i = 0; i < n; i++, o++) {
      types[i] = bd.getUint8(o);
    }
    for (var i = 0; i < n; i++, o++) {
      weights[i] = bd.getUint8(o);
    }
    return FacilityStore(lat, lng, types, weights);
  }
}

class FacilityTally {
  final int lights;
  final int cctvs;
  final int bells;

  /// 경로 주변 시설 인덱스(지도 강조 표시용).
  final List<int> indices;
  const FacilityTally(this.lights, this.cctvs, this.bells, this.indices);

  int get total => lights + cctvs + bells;
}
