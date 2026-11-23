import 'dart:typed_data';

import 'facilities.dart';
import 'geo.dart';
import 'road_graph.dart';
import 'safety_model.dart';

/// 무방향 도로 목록 → CSR [RoadGraph]. 전처리 도구와 테스트가 사용한다.
class RoadGraphBuilder {
  final _lat = <int>[];
  final _lng = <int>[];
  final _eu = <int>[];
  final _ev = <int>[];
  final _len = <double>[];
  final _flags = <int>[];
  final _feature = <int>[];
  final _name = <int>[];
  final _names = <String>[''];
  final _nameIds = <String, int>{'': 0};
  final _light = <int>[];
  final _cctv = <int>[];
  final _bell = <int>[];

  int get nodeCount => _lat.length;
  int get edgeCount => _eu.length;

  int addNode(double lat, double lng) {
    _lat.add((lat * 1e6).round());
    _lng.add((lng * 1e6).round());
    return _lat.length - 1;
  }

  double nodeLat(int i) => _lat[i] / 1e6;
  double nodeLng(int i) => _lng[i] / 1e6;

  /// 도로 이름 → 번호(같은 이름은 같은 번호)
  int nameId(String? name) {
    final s = (name ?? '').trim().replaceAll('\n', ' ');
    return _nameIds.putIfAbsent(s, () {
      _names.add(s);
      if (_names.length > 0xFFFF) throw StateError('도로 이름이 65535개를 넘습니다');
      return _names.length - 1;
    });
  }

  /// 무방향 엣지 추가. 시설 수준(0~1)은 [setLevels]로 나중에 채워도 된다.
  int addEdge(int u, int v,
      {required int flags, double? lengthM, String? name, EdgeFeature feature = EdgeFeature.none}) {
    _eu.add(u);
    _ev.add(v);
    _len.add(lengthM ?? haversineM(nodeLat(u), nodeLng(u), nodeLat(v), nodeLng(v)));
    _flags.add(flags);
    _feature.add(feature.index);
    _name.add(nameId(name));
    _light.add(0);
    _cctv.add(0);
    _bell.add(0);
    return _eu.length - 1;
  }

  void setLevels(int edge, FacilityLevels lv) {
    int q(double x) => (x.clamp(0.0, 1.0) * 255).round();
    _light[edge] = q(lv.light);
    _cctv[edge] = q(lv.cctv);
    _bell[edge] = q(lv.bell);
  }

  /// 모든 엣지의 시설 수준을 선분 샘플 평균으로 계산한다.
  void computeLevels(FacilityStore store, SafetyModel model, {double stepM = 10}) {
    for (var e = 0; e < edgeCount; e++) {
      setLevels(
          e,
          segmentLevels(store, model, nodeLat(_eu[e]), nodeLng(_eu[e]), nodeLat(_ev[e]),
              nodeLng(_ev[e]),
              stepM: stepM));
    }
  }

  RoadGraph build() {
    final n = nodeCount, m = edgeCount * 2;
    final deg = Uint32List(n + 1);
    for (var e = 0; e < edgeCount; e++) {
      deg[_eu[e] + 1]++;
      deg[_ev[e] + 1]++;
    }
    for (var i = 1; i <= n; i++) {
      deg[i] += deg[i - 1];
    }
    final offsets = Uint32List.fromList(deg);
    final fill = Uint32List.fromList(deg);
    final targets = Uint32List(m);
    final lengths = Float32List(m);
    final light = Uint8List(m), cctv = Uint8List(m), bell = Uint8List(m), flags = Uint8List(m);
    final feature = Uint8List(m);
    final name = Uint16List(m);
    void put(int from, int to, int e) {
      final k = fill[from]++;
      targets[k] = to;
      lengths[k] = _len[e];
      light[k] = _light[e];
      cctv[k] = _cctv[e];
      bell[k] = _bell[e];
      flags[k] = _flags[e];
      feature[k] = _feature[e];
      name[k] = _name[e];
    }

    for (var e = 0; e < edgeCount; e++) {
      put(_eu[e], _ev[e], e);
      put(_ev[e], _eu[e], e);
    }
    return RoadGraph(
      latE6: Int32List.fromList(_lat),
      lngE6: Int32List.fromList(_lng),
      offsets: offsets,
      targets: targets,
      lengths: lengths,
      edgeLight: light,
      edgeCctv: cctv,
      edgeBell: bell,
      edgeFlags: flags,
      edgeFeature: feature,
      edgeName: name,
      names: List.unmodifiable(_names),
    );
  }
}

/// 선분 ab를 따라 [stepM] 간격으로 시설 수준을 샘플링해 평균낸다.
FacilityLevels segmentLevels(FacilityStore store, SafetyModel model, double aLat, double aLng,
    double bLat, double bLng,
    {double stepM = 10}) {
  final len = haversineM(aLat, aLng, bLat, bLng);
  final k = (len / stepM).ceil().clamp(1, 1000);
  var l = 0.0, c = 0.0, b = 0.0;
  for (var i = 0; i <= k; i++) {
    final t = i / k;
    final lv = model.levelsAt(store, aLat + (bLat - aLat) * t, aLng + (bLng - aLng) * t);
    l += lv.light;
    c += lv.cctv;
    b += lv.bell;
  }
  return FacilityLevels(l / (k + 1), c / (k + 1), b / (k + 1));
}
