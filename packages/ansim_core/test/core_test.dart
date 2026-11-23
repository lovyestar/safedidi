import 'dart:typed_data';

import 'package:ansim_core/ansim_core.dart';
import 'package:test/test.dart';

/// 부산 서면 근처 가상 지형:
///  A ──────(어두운 직선 1000m)────── B
///  │                                │
///  └──(가로등이 촘촘한 우회로 1300m)──┘   (북쪽 150m 위)
class _Fixture {
  static const lat0 = 35.15, lng0 = 129.05;
  static final mLng = metersPerDegLng(lat0);
  static double lngAt(double m) => lng0 + m / mLng;
  static double latAt(double m) => lat0 + m / metersPerDegLat;

  late final FacilityStore facilities;
  late final RoadGraph graph;
  late final GeoPoint a, b;

  _Fixture() {
    // 우회로(북쪽 150m) 위와 양쪽 세로 구간에 25m 간격 가로등
    final lats = <int>[], lngs = <int>[];
    void light(double north, double east) {
      lats.add((latAt(north) * 1e6).round());
      lngs.add((lngAt(east) * 1e6).round());
    }

    for (var e = 0.0; e <= 1000; e += 25) {
      light(150, e);
    }
    for (var n = 0.0; n <= 150; n += 25) {
      light(n, 0);
      light(n, 1000);
    }
    // 직선 구간에는 CCTV 1대만 (점수에 거의 영향 없음)
    final store = FacilityStore(
      Int32List.fromList([...lats, (latAt(-200) * 1e6).round()]),
      Int32List.fromList([...lngs, (lngAt(500) * 1e6).round()]),
      Uint8List.fromList([...List.filled(lats.length, FacilityType.light.index), FacilityType.cctv.index]),
      Uint8List.fromList(List.filled(lats.length + 1, 1)),
    );
    facilities = store;

    final gb = RoadGraphBuilder();
    final minor = RoadFlags.encode(RoadClass.minor);
    // 직선: 0..1000m, 100m 간격
    final straight = [for (var e = 0.0; e <= 1000; e += 100) gb.addNode(latAt(0), lngAt(e))];
    for (var i = 1; i < straight.length; i++) {
      gb.addEdge(straight[i - 1], straight[i], flags: minor);
    }
    // 우회로: A → 북쪽 150m → 동쪽 1000m → 남쪽 150m → B
    final up = [straight.first, gb.addNode(latAt(75), lngAt(0)), gb.addNode(latAt(150), lngAt(0))];
    final top = [up.last, for (var e = 100.0; e < 1000; e += 100) gb.addNode(latAt(150), lngAt(e))];
    final topEnd = gb.addNode(latAt(150), lngAt(1000));
    top.add(topEnd);
    final down = [topEnd, gb.addNode(latAt(75), lngAt(1000)), straight.last];
    for (final chain in [up, top, down]) {
      for (var i = 1; i < chain.length; i++) {
        gb.addEdge(chain[i - 1], chain[i], flags: minor);
      }
    }
    gb.computeLevels(store, const SafetyModel());
    graph = gb.build();
    a = GeoPoint(latAt(0), lngAt(0));
    b = GeoPoint(latAt(0), lngAt(1000));
  }
}

void main() {
  final fx = _Fixture();

  group('geo', () {
    test('resample weights add up to polyline length', () {
      final pts = [fx.a, GeoPoint(_Fixture.latAt(0), _Fixture.lngAt(333)), fx.b];
      final samples = resamplePolyline(pts, 10);
      final sum = samples.fold<double>(0, (s, x) => s + x.weightM);
      expect(sum, closeTo(polylineLengthM(pts), 0.5));
      expect(samples.first.point, pts.first);
      expect(samples.last.point, pts.last);
    });

    test('point to segment distance', () {
      final d = pointSegmentDistanceM(_Fixture.latAt(50), _Fixture.lngAt(500), fx.a.lat, fx.a.lng,
          fx.b.lat, fx.b.lng);
      expect(d, closeTo(50, 0.5));
    });
  });

  group('binary formats', () {
    test('facilities round trip', () {
      final bytes = fx.facilities.toBytes();
      final back = FacilityStore.fromBytes(ByteData.sublistView(bytes));
      expect(back.length, fx.facilities.length);
      expect(back.latE6, fx.facilities.latE6);
      expect(back.types, fx.facilities.types);
      expect(back.countOf(FacilityType.cctv), 1);
    });

    test('graph round trip (zero-copy views)', () {
      final bytes = fx.graph.toBytes();
      final back = RoadGraph.fromBytes(ByteData.sublistView(bytes));
      expect(back.nodeCount, fx.graph.nodeCount);
      expect(back.edgeCount, fx.graph.edgeCount);
      expect(back.targets, fx.graph.targets);
      expect(back.lengths, fx.graph.lengths);
      expect(back.edgeLight, fx.graph.edgeLight);
    });

    test('graph loads from unaligned buffer', () {
      final bytes = fx.graph.toBytes();
      final padded = Uint8List(bytes.length + 1)..setAll(1, bytes);
      final back = RoadGraph.fromBytes(ByteData.sublistView(padded, 1));
      expect(back.targets, fx.graph.targets);
    });
  });

  group('router', () {
    final router = AStarRouter(fx.graph);
    final s = fx.graph.nearestNode(fx.a.lat, fx.a.lng);
    final t = fx.graph.nearestNode(fx.b.lat, fx.b.lng);

    test('alpha 0 gives the straight shortest path', () {
      final r = router.route(s, t)!;
      expect(r.lengthM, closeTo(1000, 2));
    });

    test('safety weighting takes the lit detour', () {
      final r = router.route(s, t, alpha: 5)!;
      expect(r.lengthM, closeTo(1300, 3));
    });

    test('edge scores: lit detour is brighter than the dark straight', () {
      final model = const SafetyModel();
      final straight = router.route(s, t)!;
      final detour = router.route(s, t, alpha: 5)!;
      double avg(RoutePath p) =>
          p.edges.map((e) => fx.graph.edgeScore(e, model)).reduce((x, y) => x + y) / p.edges.length;
      expect(avg(detour), greaterThan(avg(straight) + 0.2));
    });
  });

  group('planner', () {
    test('route colors use the same road-edge scores as the map layer', () {
      final planner = SafeRoutePlanner(fx.graph, fx.facilities);
      // 도로에서 조금 떨어진 출발·도착점 → 양 끝은 연결선
      final from = GeoPoint(_Fixture.latAt(-8), _Fixture.lngAt(0));
      final to = GeoPoint(_Fixture.latAt(-8), _Fixture.lngAt(1000));
      final r = planner.plan(from, to);
      final m = r.safe;
      expect(m.segmentScores.length, m.points.length - 1);
      expect(m.isConnector(0), isTrue);
      expect(m.isConnector(m.segmentEdges.length - 1), isTrue);
      for (var i = 0; i < m.segmentEdges.length; i++) {
        final e = m.segmentEdges[i];
        if (e < 0) continue;
        expect(m.segmentScores[i], closeTo(fx.graph.edgeScore(e, const SafetyModel()), 1e-9));
      }
      // 도착 연결선이 시작되는 곳 = 도로 끝(연결선 8m 앞)
      expect(m.roadEndM, closeTo(m.distanceM - 8, 0.5));
      // 안내 중 '지금 이곳' 점수: 위치가 놓인 구간을 찾아 그 구간(선 색) 점수를 쓴다
      final k = m.segmentEdges.length ~/ 2;
      final q = GeoPoint((m.points[k].lat + m.points[k + 1].lat) / 2, (m.points[k].lng + m.points[k + 1].lng) / 2);
      final prog = progressOnPolyline(m.points, q);
      expect(prog.segment, k);
      expect(m.scoreOfSegment(prog.segment), m.segmentScores[k]);
      // 보도처럼 도로에서 15m 떨어져 나란히 가는 외부 경로는 도로 위로 붙는다(처음·끝 점은 그대로)
      final side = [for (var e = 0.0; e <= 600; e += 100) GeoPoint(_Fixture.latAt(15), _Fixture.lngAt(e))];
      final snapped = planner.analyzer.snapToRoads(side);
      for (final q in snapped.sublist(1, snapped.length - 1)) {
        expect(distanceM(q, GeoPoint(_Fixture.latAt(0), q.lng)), lessThan(1));
      }
      expect(snapped.first, side.first);
      // 외부(TMAP) 경로도 같은 도로면 같은 점수로 맞춰진다
      final ext = planner.analyzer.analyze([fx.a, fx.b]);
      expect(ext.segmentEdges.where((e) => e >= 0), isNotEmpty);
    });

    final planner = SafeRoutePlanner(fx.graph, fx.facilities);

    test('compares shortest vs safe route', () {
      final res = planner.plan(fx.a, fx.b);
      final c = res.comparison;
      expect(c.identical, isFalse);
      expect(res.generalSource, GeneralRouteSource.internal);
      expect(c.extraMeters, closeTo(300, 5));
      expect(c.extraLights, greaterThan(30));
      expect(c.scoreGain, greaterThan(20));
      expect(c.darkAvoided, greaterThanOrEqualTo(1));
      expect(c.message, contains('더 걷지만'));
      expect(c.message, contains('보안등'));
      expect(c.headline, startsWith('최단 '));
    });

    test('external (TMAP) polyline is scored with the same model', () {
      final ext = [fx.a, fx.b];
      final res = planner.plan(fx.a, fx.b, externalGeneral: ext);
      expect(res.generalSource, GeneralRouteSource.tmap);
      expect(res.general.distanceM, closeTo(1000, 2));
      expect(res.safe.safetyScore, greaterThan(res.general.safetyScore));
    });

    test('TMAP route longer than the safe route: message says shorter, not "more walking"', () {
      // TMAP이 남쪽으로 200m 내려갔다 오는 어두운 길(1400m)을 줬다 → 안심 경로(1300m)가 더 짧다
      final ext = [
        fx.a,
        GeoPoint(_Fixture.latAt(-200), _Fixture.lngAt(0)),
        GeoPoint(_Fixture.latAt(-200), _Fixture.lngAt(1000)),
        fx.b,
      ];
      final c = planner.plan(fx.a, fx.b, externalGeneral: ext).comparison;
      expect(c.identical, isFalse);
      expect(c.extraMeters, closeTo(-100, 5));
      expect(c.safeIsShorter, isTrue);
      expect(c.message, startsWith('100m'));
      expect(c.message, contains('더 짧은데'));
      expect(c.message, contains('안심지수도'));
      expect(c.message, isNot(contains('더 걷지만')));
      expect(c.headline, startsWith('안심 '));
    });

    test('rejects points outside Busan', () {
      expect(() => planner.plan(const GeoPoint(37.5665, 126.978), fx.b),
          throwsA(isA<PlanException>()));
    });

    test('safety raster: lit detour bright, straight dark, off-road empty, round trip', () {
      final r = SafetyRaster.build(fx.graph, fx.facilities, cellM: 20);
      final mid = _Fixture.lngAt(500);
      expect(r.scoreAt(_Fixture.latAt(150), mid)!, greaterThan(0.4), reason: '가로등 우회로');
      expect(r.scoreAt(_Fixture.latAt(0), mid)!, lessThan(0.25), reason: '어두운 직선');
      expect(r.scoreAt(_Fixture.latAt(75), mid), isNull, reason: '도로 없는 곳');
      final back = SafetyRaster.fromBytes(ByteData.sublistView(r.toBytes()));
      expect(back.rows, r.rows);
      expect(back.values, r.values);
      expect(back.scoreAt(_Fixture.latAt(150), mid), r.scoreAt(_Fixture.latAt(150), mid));
    });

    test('heatmap marks road cells and leaves empty cells transparent', () {
      final hm = SafetyHeatmap.compute(
          fx.facilities, GeoBounds.fromPoints([fx.a, fx.b]).expandedBy(300),
          roadMask: fx.graph, cols: 40, rows: 60);
      expect(hm.values.where((v) => v < 0), isNotEmpty, reason: '도로 없는 칸은 투명');
      expect(hm.values.where((v) => v > 0.3), isNotEmpty, reason: '가로등 우회로는 밝게');
      expect(hm.values.where((v) => v >= 0 && v < 0.05), isNotEmpty, reason: '어두운 직선로');
    });
  });
}
