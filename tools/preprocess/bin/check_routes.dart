// 생성된 assets로 실제 부산 경로를 계산해 보는 점검 도구.
// 실행: cd tools/preprocess && dart run bin/check_routes.dart [--data ../../app/assets/data]

import 'dart:io';
import 'dart:typed_data';

import 'package:ansim_core/ansim_core.dart';

void main(List<String> args) {
  final i = args.indexOf('--data');
  final dir = i >= 0 && i + 1 < args.length ? args[i + 1] : '../../app/assets/data';
  final sw = Stopwatch()..start();
  final graph = RoadGraph.fromBytes(ByteData.sublistView(File('$dir/graph.bin').readAsBytesSync()));
  final store = FacilityStore.fromBytes(ByteData.sublistView(File('$dir/facilities.bin').readAsBytesSync()));
  final planner = SafeRoutePlanner(graph, store);
  // 인덱스·엣지 점수 미리 생성
  graph.nodeIndex;
  store.index;
  planner.router.edgeScores;
  print('로드 ${sw.elapsedMilliseconds}ms (노드 ${graph.nodeCount}, 시설 ${store.length})');

  const cases = <(String, GeoPoint, GeoPoint)>[
    ('서면역 → 전포카페거리', GeoPoint(35.1577, 129.0594), GeoPoint(35.1547, 129.0640)),
    ('부산대역 → 장전동 원룸촌', GeoPoint(35.2297, 129.0890), GeoPoint(35.2355, 129.0820)),
    ('경성대·부경대역 → 대연동 주택가', GeoPoint(35.1376, 129.1004), GeoPoint(35.1320, 129.0935)),
    ('부산역 → 초량 이바구길', GeoPoint(35.1151, 129.0414), GeoPoint(35.1185, 129.0350)),
    ('해운대역 → 우동 주택가', GeoPoint(35.1631, 129.1588), GeoPoint(35.1680, 129.1530)),
    ('서면 → 부산시청 (약 3km)', GeoPoint(35.1577, 129.0594), GeoPoint(35.1798, 129.0750)),
    ('남포동 → 영도 봉래동 (다리 건넘)', GeoPoint(35.0979, 129.0306), GeoPoint(35.0930, 129.0420)),
  ];
  for (final (name, a, b) in cases) {
    final t = Stopwatch()..start();
    try {
      final r = planner.plan(a, b);
      final c = r.comparison;
      print('\n■ $name  (${t.elapsedMilliseconds}ms, alpha ${r.alpha}, 확장노드 ${planner.router.lastExpanded})');
      print('  일반: ${c.general.distanceM.round()}m ${c.general.minutes}분 안심지수 ${c.general.safetyScore} '
          '어두운구간 ${c.general.darkSegments} 가로등 ${c.general.tally.lights} CCTV ${c.general.tally.cctvs}');
      print('  안심: ${c.safe.distanceM.round()}m ${c.safe.minutes}분 안심지수 ${c.safe.safetyScore} '
          '어두운구간 ${c.safe.darkSegments} 가로등 ${c.safe.tally.lights} CCTV ${c.safe.tally.cctvs}');
      print('  ${c.headline}');
      print('  ${c.message}');
      final ms = buildManeuvers(c.safe.points, graph, roadEndM: c.safe.roadEndM);
      print('  길 안내 ${ms.length - 2}곳: ${ms.map((m) => '${m.atM.round()}m ${m.title}${m.road == null ? '' : '(${m.road})'}').join(' → ')}');
    } on PlanException catch (e) {
      print('\n■ $name  실패: ${e.message}');
    }
  }
}
