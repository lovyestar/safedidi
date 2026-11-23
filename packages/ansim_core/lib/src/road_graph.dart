import 'dart:convert';
import 'dart:typed_data';

import 'geo.dart';
import 'grid_index.dart';
import 'safety_model.dart';

/// 보행 도로망 그래프(CSR 인접 리스트). 양방향 도로는 방향별 엣지 2개로 저장한다.
///
/// 바이너리 포맷(little-endian, 헤더 24바이트):
///   u32 magic 'ADGR', u16 version(2), u16 reserved, u32 nodeCount, u32 edgeCount, u32 0, u32 0,
///   i32 latE6[n], i32 lngE6[n], u32 offsets[n+1], u32 targets[m], f32 lengthM[m],
///   u8 light[m], u8 cctv[m], u8 bell[m], u8 roadFlags[m],
///   (v2) u8 feature[m], 4바이트 정렬 패딩, u16 nameId[m], 패딩, u32 nameBytes, UTF-8 이름들('\n' 구분, 0번은 이름 없음)
/// light/cctv/bell은 엣지 주변 시설 밀집도(0~1)를 0~255로 양자화한 값.
/// feature는 [EdgeFeature](횡단보도·육교·지하도·계단), nameId는 도로 이름(길 안내 문구용).
class RoadGraph {
  static const int magic = 0x52474441; // 'ADGR'
  static const int version = 2;
  static const int headerBytes = 24;

  final Int32List latE6;
  final Int32List lngE6;
  final Uint32List offsets;
  final Uint32List targets;
  final Float32List lengths;
  final Uint8List edgeLight;
  final Uint8List edgeCctv;
  final Uint8List edgeBell;
  final Uint8List edgeFlags;

  /// 엣지 특징([EdgeFeature] index). v1 파일이면 모두 0.
  final Uint8List edgeFeature;

  /// 엣지 도로 이름 번호([names]의 index, 0 = 이름 없음).
  final Uint16List edgeName;

  /// 도로 이름 목록. 0번은 빈 문자열.
  final List<String> names;

  late final GridIndex nodeIndex = GridIndex.build(
    count: nodeCount,
    latOf: lat,
    lngOf: lng,
    cellSizeM: 60,
  );

  RoadGraph({
    required this.latE6,
    required this.lngE6,
    required this.offsets,
    required this.targets,
    required this.lengths,
    required this.edgeLight,
    required this.edgeCctv,
    required this.edgeBell,
    required this.edgeFlags,
    Uint8List? edgeFeature,
    Uint16List? edgeName,
    this.names = const [''],
  })  : edgeFeature = edgeFeature ?? Uint8List(targets.length),
        edgeName = edgeName ?? Uint16List(targets.length);

  /// 엣지 도로 이름(없으면 null)
  String? nameOf(int e) {
    final id = edgeName[e];
    return id == 0 || id >= names.length ? null : names[id];
  }

  EdgeFeature featureOf(int e) => EdgeFeature.values[edgeFeature[e].clamp(0, EdgeFeature.values.length - 1)];

  /// 노드에 붙은 길 수(교차로 판단용)
  int degree(int u) => offsets[u + 1] - offsets[u];

  int get nodeCount => latE6.length;
  int get edgeCount => targets.length;
  double lat(int i) => latE6[i] / 1e6;
  double lng(int i) => lngE6[i] / 1e6;
  GeoPoint point(int i) => GeoPoint(lat(i), lng(i));

  /// 엣지 e의 출발 노드(CSR이라 이진 탐색).
  int sourceOf(int e) {
    var lo = 0, hi = nodeCount - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (offsets[mid] <= e) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  double edgeScore(int e, SafetyModel model) => model.score(
      edgeLight[e] / 255.0, edgeCctv[e] / 255.0, edgeBell[e] / 255.0, edgeFlags[e]);

  Float32List computeEdgeScores(SafetyModel model) {
    final out = Float32List(edgeCount);
    for (var e = 0; e < edgeCount; e++) {
      out[e] = edgeScore(e, model);
    }
    return out;
  }

  /// 가장 가까운 노드. [maxM] 안에 없으면 -1.
  int nearestNode(double lat, double lng, {double maxM = 300}) {
    var best = -1;
    var bestD = double.infinity;
    for (final r in [40.0, 120.0, maxM]) {
      if (r > maxM) continue;
      nodeIndex.forEachCandidate(lat, lng, r, (i) {
        final d = haversineM(lat, lng, this.lat(i), this.lng(i));
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      });
      if (best >= 0 && bestD <= r) break;
    }
    return bestD <= maxM ? best : -1;
  }

  /// 가장 가까운 엣지와 거리. 근처 노드에 붙은 엣지만 검사한다.
  ({int edge, double distanceM}) nearestEdge(double lat, double lng, {double maxM = 30}) {
    var best = -1;
    var bestD = double.infinity;
    nodeIndex.forEachCandidate(lat, lng, maxM + 80, (u) {
      final uLat = this.lat(u), uLng = this.lng(u);
      for (var e = offsets[u]; e < offsets[u + 1]; e++) {
        final v = targets[e];
        final d = pointSegmentDistanceM(lat, lng, uLat, uLng, this.lat(v), this.lng(v));
        if (d < bestD) {
          bestD = d;
          best = e;
        }
      }
    });
    return bestD <= maxM ? (edge: best, distanceM: bestD) : (edge: -1, distanceM: bestD);
  }

  static int _pad4(int o) => (o + 3) & ~3;

  Uint8List toBytes() {
    final n = nodeCount, m = edgeCount;
    final nameBytes = utf8.encode(names.join('\n'));
    var size = headerBytes + n * 8 + (n + 1) * 4 + m * 4 + m * 4 + m * 4 + m;
    size = _pad4(size) + m * 2;
    size = _pad4(size) + 4 + nameBytes.length;
    final bd = ByteData(size);
    bd.setUint32(0, magic, Endian.little);
    bd.setUint16(4, version, Endian.little);
    bd.setUint32(8, n, Endian.little);
    bd.setUint32(12, m, Endian.little);
    var o = headerBytes;
    for (var i = 0; i < n; i++, o += 4) {
      bd.setInt32(o, latE6[i], Endian.little);
    }
    for (var i = 0; i < n; i++, o += 4) {
      bd.setInt32(o, lngE6[i], Endian.little);
    }
    for (var i = 0; i <= n; i++, o += 4) {
      bd.setUint32(o, offsets[i], Endian.little);
    }
    for (var i = 0; i < m; i++, o += 4) {
      bd.setUint32(o, targets[i], Endian.little);
    }
    for (var i = 0; i < m; i++, o += 4) {
      bd.setFloat32(o, lengths[i], Endian.little);
    }
    for (final arr in [edgeLight, edgeCctv, edgeBell, edgeFlags, edgeFeature]) {
      for (var i = 0; i < m; i++, o++) {
        bd.setUint8(o, arr[i]);
      }
    }
    o = _pad4(o);
    for (var i = 0; i < m; i++, o += 2) {
      bd.setUint16(o, edgeName[i], Endian.little);
    }
    o = _pad4(o);
    bd.setUint32(o, nameBytes.length, Endian.little);
    o += 4;
    bd.buffer.asUint8List().setAll(o, nameBytes);
    return bd.buffer.asUint8List();
  }

  /// 바이트에서 그래프를 읽는다. 정렬이 맞으면 복사 없이 뷰를 만든다.
  factory RoadGraph.fromBytes(ByteData input) {
    var bd = input;
    if (bd.getUint32(0, Endian.little) != magic) {
      throw const FormatException('graph.bin 형식이 아닙니다');
    }
    final ver = bd.getUint16(4, Endian.little);
    if (ver != 1 && ver != 2) throw FormatException('지원하지 않는 graph.bin 버전: $ver');
    if (Endian.host != Endian.little || bd.offsetInBytes % 4 != 0) {
      // 정렬이 어긋난 경우 새 버퍼로 복사
      final copy = Uint8List(bd.lengthInBytes)
        ..setAll(0, bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes));
      bd = ByteData.sublistView(copy);
    }
    final n = bd.getUint32(8, Endian.little);
    final m = bd.getUint32(12, Endian.little);
    final buf = bd.buffer;
    var o = bd.offsetInBytes + headerBytes;
    final lat = buf.asInt32List(o, n);
    o += n * 4;
    final lng = buf.asInt32List(o, n);
    o += n * 4;
    final offsets = buf.asUint32List(o, n + 1);
    o += (n + 1) * 4;
    final targets = buf.asUint32List(o, m);
    o += m * 4;
    final lengths = buf.asFloat32List(o, m);
    o += m * 4;
    final light = buf.asUint8List(o, m);
    o += m;
    final cctv = buf.asUint8List(o, m);
    o += m;
    final bell = buf.asUint8List(o, m);
    o += m;
    final flags = buf.asUint8List(o, m);
    o += m;
    Uint8List? feature;
    Uint16List? nameId;
    var names = const [''];
    if (ver >= 2) {
      feature = buf.asUint8List(o, m);
      o += m;
      final base = bd.offsetInBytes;
      o = base + _pad4(o - base);
      nameId = buf.asUint16List(o, m);
      o += m * 2;
      o = base + _pad4(o - base);
      final len = bd.getUint32(o - base, Endian.little);
      o += 4;
      names = utf8.decode(buf.asUint8List(o, len)).split('\n');
    }
    return RoadGraph(
      latE6: lat,
      lngE6: lng,
      offsets: offsets,
      targets: targets,
      lengths: lengths,
      edgeLight: light,
      edgeCctv: cctv,
      edgeBell: bell,
      edgeFlags: flags,
      edgeFeature: feature,
      edgeName: nameId,
      names: names,
    );
  }
}

/// 길 안내에 쓰는 도로 특징.
enum EdgeFeature {
  none,

  /// 횡단보도(footway=crossing)
  crossing,

  /// 육교(짧은 보행 다리)
  overpass,

  /// 지하도·지하보도
  underpass,

  /// 계단
  steps,
}
