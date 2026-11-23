import 'analysis.dart';
import 'facilities.dart';
import 'geo.dart';
import 'road_graph.dart';
import 'router.dart';
import 'safety_model.dart';

enum GeneralRouteSource {
  /// TMAP 보행자 경로 API
  tmap,

  /// 앱 내장 그래프의 순수 최단거리(Dijkstra/A*, alpha=0)
  internal,
}

class PlanException implements Exception {
  final String message;
  const PlanException(this.message);
  @override
  String toString() => message;
}

class PlanResult {
  final GeoPoint from;
  final GeoPoint to;
  final RouteComparison comparison;
  final GeneralRouteSource generalSource;

  /// 안심 경로 탐색에 쓴 alpha(0이면 최단 경로를 그대로 사용).
  final double alpha;

  /// 탐색에 걸린 시간(ms).
  final int elapsedMs;

  const PlanResult({
    required this.from,
    required this.to,
    required this.comparison,
    required this.generalSource,
    required this.alpha,
    required this.elapsedMs,
  });

  RouteMetrics get general => comparison.general;
  RouteMetrics get safe => comparison.safe;
}

/// 출발·도착 좌표 → 일반 경로 + 안심 경로 + 대조 결과.
class SafeRoutePlanner {
  final RoadGraph graph;
  final FacilityStore facilities;
  final SafetyModel model;
  late final AStarRouter router = AStarRouter(graph, model: model);
  late final RouteAnalyzer analyzer = RouteAnalyzer(graph, facilities, model: model);

  /// 강한 회피부터 시도해서, 우회 한도 안에 들어오는 첫 경로를 쓴다.
  static const List<double> alphaSchedule = [8, 5, 3, 1.8, 1];

  /// 안심 경로 길이 한도 = 최단 × ratio + extra
  final double maxDetourRatio;
  final double maxDetourExtraM;

  /// 출발·도착점을 도로망에 붙일 때 허용 거리.
  final double snapMaxM;

  /// 별도 안심 경로를 추천하려면 필요한 최소 안심점수 차이(0~1, 0.03 = 3점).
  final double minScoreGain;

  SafeRoutePlanner(
    this.graph,
    this.facilities, {
    this.model = const SafetyModel(),
    this.maxDetourRatio = 1.5,
    this.maxDetourExtraM = 200,
    this.snapMaxM = 400,
    this.minScoreGain = 0.03,
  });

  int snap(GeoPoint p) {
    final n = graph.nearestNode(p.lat, p.lng, maxM: snapMaxM);
    if (n < 0) {
      throw const PlanException('근처에 걸어갈 수 있는 도로가 없어요. 위치를 다시 골라주세요.');
    }
    return n;
  }

  /// [externalGeneral]가 있으면(TMAP 경로) 그것을 일반 경로로 쓰고,
  /// 없으면 내장 그래프의 최단 경로를 일반 경로로 쓴다.
  PlanResult plan(GeoPoint from, GeoPoint to, {List<GeoPoint>? externalGeneral}) {
    final sw = Stopwatch()..start();
    if (!busanBounds.contains(from.lat, from.lng) || !busanBounds.contains(to.lat, to.lng)) {
      throw const PlanException('안심 경로는 부산광역시 안에서만 계산할 수 있어요.');
    }
    final s = snap(from), t = snap(to);
    final shortest = router.route(s, t);
    if (shortest == null) {
      throw const PlanException('두 지점을 잇는 보행 경로를 찾지 못했어요.');
    }
    final limit = shortest.lengthM * maxDetourRatio + maxDetourExtraM;
    RoutePath safe = shortest;
    var alphaUsed = 0.0;
    for (final a in alphaSchedule) {
      final r = router.route(s, t, alpha: a);
      if (r != null && r.lengthM <= limit) {
        safe = r;
        alphaUsed = a;
        break;
      }
    }

    // 앱이 찾은 경로는 도로 조각(엣지) 번호와 함께 채점해 지도 '도로 밝기'와 같은 점수를 쓴다
    final safeRoute = _withEnds(from, safe, to);
    final RouteMetrics generalM;
    if (externalGeneral != null && externalGeneral.length >= 2) {
      generalM = analyzer.analyze(externalGeneral);
    } else {
      final g = _withEnds(from, shortest, to);
      generalM = analyzer.analyze(g.points, edges: g.edges);
    }
    var safeM = analyzer.analyze(safeRoute.points, edges: safeRoute.edges);
    var identical = externalGeneral == null && _sameNodes(safe, shortest);

    // 안심지수가 의미 있게(minGain 이상) 높지 않으면 하나만 추천한다.
    // TMAP 경로는 지도(OSM)와 선이 조금 어긋날 수 있어, 추천 경로는 앱이 찾은 경로(지도와 같은 도로망)로 그린다.
    if (!identical && safeM.avgScore < generalM.avgScore + minScoreGain) identical = true;
    if (identical && externalGeneral == null) safeM = generalM;

    return PlanResult(
      from: from,
      to: to,
      comparison: RouteComparison(generalM, safeM, identical: identical),
      generalSource: externalGeneral != null ? GeneralRouteSource.tmap : GeneralRouteSource.internal,
      alpha: alphaUsed,
      elapsedMs: sw.elapsedMilliseconds,
    );
  }

  static bool _sameNodes(RoutePath a, RoutePath b) {
    if (a.nodes.length != b.nodes.length) return false;
    for (var i = 0; i < a.nodes.length; i++) {
      if (a.nodes[i] != b.nodes[i]) return false;
    }
    return true;
  }

  /// 출발점 → (연결선) → 도로망 경로 → (연결선) → 도착점. 구간마다 엣지 번호를 함께 돌려준다.
  ({List<GeoPoint> points, List<int> edges}) _withEnds(GeoPoint from, RoutePath path, GeoPoint to) {
    final mid = path.points(graph);
    final pts = <GeoPoint>[];
    final edges = <int>[];
    if (mid.isEmpty) return (points: [from, to], edges: [RouteAnalyzer.connectorEdge]);
    if (distanceM(from, mid.first) > 0.5) {
      pts.add(from);
      edges.add(RouteAnalyzer.connectorEdge);
    }
    for (var i = 0; i < mid.length; i++) {
      pts.add(mid[i]);
      if (i < mid.length - 1) edges.add(path.edges[i]);
    }
    if (distanceM(mid.last, to) > 0.5) {
      edges.add(RouteAnalyzer.connectorEdge);
      pts.add(to);
    }
    return (points: pts, edges: edges);
  }
}
