import 'dart:math' as math;

import 'facilities.dart';
import 'geo.dart';
import 'road_graph.dart';
import 'safety_model.dart';

/// 한 경로의 안전 지표.
class RouteMetrics {
  final List<GeoPoint> points;
  final double distanceM;
  final int minutes;

  /// 길이 가중 평균 안심점수(0~1).
  final double avgScore;

  /// 30m 이상 이어지는 어두운 구간 수.
  final int darkSegments;
  final double darkLengthM;
  final FacilityTally tally;

  /// 밝기 막대·통계용: 10m 간격 샘플 점과 점수(점수는 그 점이 속한 도로 조각 점수).
  final List<GeoPoint> samplePoints;
  final List<double> sampleScores;

  /// 지도 색칠용: [points]의 구간(i → i+1)마다 안심점수와 도로망 엣지 번호.
  /// 엣지 번호가 [RouteAnalyzer.connectorEdge]면 출발·도착점을 도로에 잇는 연결선(도로 밖).
  final List<double> segmentScores;
  final List<int> segmentEdges;

  const RouteMetrics({
    required this.points,
    required this.distanceM,
    required this.minutes,
    required this.avgScore,
    required this.darkSegments,
    required this.darkLengthM,
    required this.tally,
    required this.samplePoints,
    required this.sampleScores,
    this.segmentScores = const [],
    this.segmentEdges = const [],
  });

  bool isConnector(int segment) =>
      segment < segmentEdges.length && segmentEdges[segment] == RouteAnalyzer.connectorEdge;

  /// 도착 쪽 연결선이 시작되는 곳(도로를 벗어나는 지점)까지 거리(m). 연결선이 없으면 null.
  double? get roadEndM {
    if (segmentEdges.length != points.length - 1 || segmentEdges.isEmpty) return null;
    var k = segmentEdges.length;
    while (k > 0 && segmentEdges[k - 1] == RouteAnalyzer.connectorEdge) {
      k--;
    }
    if (k == segmentEdges.length || k == 0) return null;
    return polylineLengthM(points.sublist(0, k + 1));
  }

  /// 경로 위 [segment] 구간의 안심점수(지도 선 색과 같은 값). 범위 밖이면 null.
  double? scoreOfSegment(int segment) =>
      segment >= 0 && segment < segmentScores.length ? segmentScores[segment] : null;

  /// 화면 표시용 안심지수(0~100).
  int get safetyScore => (avgScore * 100).round();
}

/// 임의의 폴리라인(직접 계산 경로든 TMAP 경로든)을 같은 기준으로 채점한다.
class RouteAnalyzer {
  final RoadGraph graph;
  final FacilityStore facilities;
  final SafetyModel model;

  /// 야간 보행 속도(m/분). 약 4km/h.
  static const double walkMetersPerMinute = 67;
  static const double sampleStepM = 10;
  static const double minDarkRunM = 30;

  /// 출발·도착점과 도로망을 잇는 연결선 표시(엣지 아님)
  static const int connectorEdge = -2;

  /// 외부 경로(TMAP)를 도로망에 맞출 때 나누는 최대 길이
  static const double matchStepM = 15;

  const RouteAnalyzer(this.graph, this.facilities, {this.model = const SafetyModel()});

  /// 샘플 지점의 도로 등급(가까운 도로가 없으면 골목으로 간주).
  int roadFlagsAt(double lat, double lng) {
    final near = graph.nearestEdge(lat, lng, maxM: 25);
    return near.edge >= 0 ? graph.edgeFlags[near.edge] : RoadFlags.encode(RoadClass.minor);
  }

  double scoreAt(double lat, double lng) {
    final lv = model.levelsAt(facilities, lat, lng);
    return model.score(lv.light, lv.cctv, lv.bell, roadFlagsAt(lat, lng));
  }

  /// 경로 채점. [edges]가 있으면(앱이 직접 찾은 경로) 구간마다 그 도로 조각의 점수를 그대로 쓴다
  /// — 지도 '도로 밝기'와 길찾기(A*)가 쓰는 점수와 같아서 색이 어긋나지 않는다.
  /// 없으면(TMAP 경로) 15m 단위로 나눠 방향이 맞는 가까운 도로 조각에 맞추고, 못 맞추면 그 지점 점수를 쓴다.
  RouteMetrics analyze(List<GeoPoint> points, {List<int>? edges}) {
    var pts = points;
    var segEdges = edges;
    if (segEdges == null || segEdges.length != pts.length - 1) {
      // TMAP 경로는 보도를 따라가 지도(OSM 도로 가운데선)와 나란히 떠 보인다 → 같은 방향의 가까운 도로에 붙인다
      pts = snapToRoads(_densify(points, matchStepM));
      segEdges = [for (var i = 0; i < pts.length - 1; i++) _matchEdge(pts[i], pts[i + 1])];
    }
    final segScores = <double>[];
    for (var i = 0; i < pts.length - 1; i++) {
      final e = segEdges[i];
      if (e >= 0) {
        segScores.add(graph.edgeScore(e, model));
      } else {
        final a = pts[i], b = pts[i + 1];
        segScores.add(scoreAt((a.lat + b.lat) / 2, (a.lng + b.lng) / 2));
      }
    }
    // 연결선은 이어지는 도로 조각 점수로(도로 밖 짧은 선이 통계를 흔들지 않게)
    for (var i = 0; i < segScores.length; i++) {
      if (segEdges[i] != connectorEdge) continue;
      final j = i == 0 ? 1 : i - 1;
      if (j >= 0 && j < segScores.length && segEdges[j] != connectorEdge) segScores[i] = segScores[j];
    }

    // 10m 샘플: 점수는 그 샘플이 놓인 구간 점수
    final samples = <GeoPoint>[];
    final sampleScores = <double>[];
    var weighted = 0.0, total = 0.0;
    var run = 0.0, darkLen = 0.0;
    var darkSegs = 0;
    void addSample(GeoPoint p, double sc, double w) {
      samples.add(p);
      sampleScores.add(sc);
      if (w <= 0) return;
      weighted += sc * w;
      total += w;
      if (sc < model.darkThreshold) {
        run += w;
      } else {
        if (run >= minDarkRunM) {
          darkSegs++;
          darkLen += run;
        }
        run = 0;
      }
    }

    if (pts.length < 2) {
      final sc = pts.isEmpty ? 0.0 : scoreAt(pts.first.lat, pts.first.lng);
      if (pts.isNotEmpty) addSample(pts.first, sc, 0);
    } else {
      addSample(pts.first, segScores.first, 0);
      var carry = 0.0;
      for (var i = 0; i < pts.length - 1; i++) {
        final a = pts[i], b = pts[i + 1];
        final seg = distanceM(a, b);
        if (seg == 0) continue;
        var pos = sampleStepM - carry;
        while (pos <= seg) {
          final t = pos / seg;
          addSample(GeoPoint(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t), segScores[i], sampleStepM);
          pos += sampleStepM;
        }
        carry = seg - (pos - sampleStepM);
      }
      if (carry > 0.01) addSample(pts.last, segScores.last, carry);
    }
    if (run >= minDarkRunM) {
      darkSegs++;
      darkLen += run;
    }
    final dist = polylineLengthM(pts);
    final avg = total > 0 ? weighted / total : (sampleScores.isNotEmpty ? sampleScores.first : 0.0);
    return RouteMetrics(
      points: pts,
      distanceM: dist,
      minutes: minutesFor(dist),
      avgScore: avg,
      darkSegments: darkSegs,
      darkLengthM: darkLen,
      tally: facilities.tallyAlong(pts),
      samplePoints: samples,
      sampleScores: sampleScores,
      segmentScores: segScores,
      segmentEdges: segEdges,
    );
  }

  /// 외부 경로 점을 같은 방향의 가까운 도로(25m 안)에 붙인다. 처음·끝 점(실제 출발·도착)은 그대로 둔다.
  /// 모퉁이 점은 들어오는 방향이나 나가는 방향 중 맞는 도로에 붙는다. 맞는 도로가 없으면 원래 점.
  List<GeoPoint> snapToRoads(List<GeoPoint> pts, {double maxM = 25}) {
    if (pts.length < 3) return pts;
    final out = <GeoPoint>[pts.first];
    for (var i = 1; i < pts.length - 1; i++) {
      final p = pts[i];
      final inB = _bearing(pts[i - 1].lat, pts[i - 1].lng, p.lat, p.lng);
      final outB = _bearing(p.lat, p.lng, pts[i + 1].lat, pts[i + 1].lng);
      out.add(_snapPoint(p, [inB, outB], maxM) ?? p);
    }
    out.add(pts.last);
    return out;
  }

  GeoPoint? _snapPoint(GeoPoint p, List<double> dirs, double maxM) {
    var best = maxM;
    GeoPoint? bestP;
    final kx = metersPerDegLng(p.lat), ky = metersPerDegLat;
    graph.nodeIndex.forEachCandidate(p.lat, p.lng, maxM + 80, (u) {
      final uLat = graph.lat(u), uLng = graph.lng(u);
      for (var e = graph.offsets[u]; e < graph.offsets[u + 1]; e++) {
        final v = graph.targets[e];
        if (v < u) continue; // 양방향 중 한쪽만
        final vLat = graph.lat(v), vLng = graph.lng(v);
        final eb = _bearing(uLat, uLng, vLat, vLng);
        var ok = false;
        for (final d in dirs) {
          var diff = (d - eb).abs() % 180;
          if (diff > 90) diff = 180 - diff;
          if (diff <= 35) ok = true;
        }
        if (!ok) continue;
        // 선분 u-v 위로 수직 투영(미터 평면 근사)
        final ax = 0.0, ay = 0.0;
        final bx = (vLng - uLng) * kx, by = (vLat - uLat) * ky;
        final px = (p.lng - uLng) * kx, py = (p.lat - uLat) * ky;
        final len2 = bx * bx + by * by;
        final t = len2 == 0 ? 0.0 : (((px - ax) * bx + (py - ay) * by) / len2).clamp(0.0, 1.0);
        final qx = bx * t, qy = by * t;
        final d = math.sqrt((px - qx) * (px - qx) + (py - qy) * (py - qy));
        if (d < best) {
          best = d;
          bestP = GeoPoint(uLat + qy / ky, uLng + qx / kx);
        }
      }
    });
    return bestP;
  }

  /// 구간을 [stepM] 이하로 잘게 나눈다(모양은 그대로).
  static List<GeoPoint> _densify(List<GeoPoint> pts, double stepM) {
    if (pts.length < 2) return pts;
    final out = <GeoPoint>[pts.first];
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], b = pts[i];
      final seg = distanceM(a, b);
      final k = (seg / stepM).ceil();
      for (var j = 1; j <= k; j++) {
        final t = j / k;
        out.add(GeoPoint(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t));
      }
    }
    return out;
  }

  /// 구간 a→b와 겹치는 도로 조각: 가운데에서 12m 안이고 방향이 30° 안으로 맞는 엣지. 없으면 -1.
  int _matchEdge(GeoPoint a, GeoPoint b) {
    final mLat = (a.lat + b.lat) / 2, mLng = (a.lng + b.lng) / 2;
    final near = graph.nearestEdge(mLat, mLng, maxM: 12);
    if (near.edge < 0) return -1;
    if (distanceM(a, b) < 2) return near.edge;
    final u = graph.sourceOf(near.edge), v = graph.targets[near.edge];
    final d1 = _bearing(a.lat, a.lng, b.lat, b.lng);
    final d2 = _bearing(graph.lat(u), graph.lng(u), graph.lat(v), graph.lng(v));
    var diff = (d1 - d2).abs() % 180;
    if (diff > 90) diff = 180 - diff;
    return diff <= 30 ? near.edge : -1;
  }

  static double _bearing(double aLat, double aLng, double bLat, double bLng) {
    final dy = (bLat - aLat) * metersPerDegLat;
    final dx = (bLng - aLng) * metersPerDegLng(aLat);
    return math.atan2(dx, dy) * 180 / math.pi;
  }

  static int minutesFor(double meters) {
    final m = (meters / walkMetersPerMinute).round();
    return m < 1 ? 1 : m;
  }
}

/// 일반(최단) 경로 vs 안심 경로 대조.
class RouteComparison {
  final RouteMetrics general;
  final RouteMetrics safe;

  /// 두 경로가 사실상 같은 길인지.
  final bool identical;

  const RouteComparison(this.general, this.safe, {this.identical = false});

  int get extraMeters => (safe.distanceM - general.distanceM).round();
  int get extraMinutes => safe.minutes - general.minutes;
  int get scoreGain => safe.safetyScore - general.safetyScore;
  int get extraLights => safe.tally.lights - general.tally.lights;
  int get extraCctvs => safe.tally.cctvs - general.tally.cctvs;
  int get extraBells => safe.tally.bells - general.tally.bells;
  int get darkAvoided => general.darkSegments - safe.darkSegments;

  /// 안심 경로가 비교 경로보다 20m 넘게 짧은지. 외부(TMAP) 경로가 돌아가는 길일 때 생긴다.
  /// 이때 비교 경로는 '최단'이 아니므로 화면·문구에서 최단이라고 부르지 않는다.
  bool get safeIsShorter => !identical && extraMeters < -20;

  /// 예: "최단 3분 vs 안심 5분", 안심 경로가 더 짧으면 "안심 11분 vs 일반 12분"
  String get headline {
    if (identical) return '최단 경로가 곧 안심 경로 · ${safe.minutes}분';
    if (safeIsShorter) return '안심 ${safe.minutes}분 vs 일반 ${general.minutes}분';
    return '최단 ${general.minutes}분 vs 안심 ${safe.minutes}분';
  }

  /// 예: "217m(3분) 더 걷지만 보안등 36개, CCTV 5대를 더 지나고
  ///      어두운 구간 5곳을 피해 안심지수가 33점 높은 길이에요."
  ///      안심 경로가 더 짧으면 "120m(2분) 더 짧은데 보안등 4개를 더 지나고 안심지수도 17점 높아요."
  String get message {
    if (identical) {
      return '최단 경로가 이미 주변보다 밝은 길이라 그대로 추천해요. '
          '경로 주변 보안등 ${safe.tally.lights}개, CCTV ${safe.tally.cctvs}대.';
    }
    final buf = StringBuffer();
    final ex = extraMeters;
    final shorter = safeIsShorter;
    if (shorter) {
      buf.write('${-ex}m');
      if (extraMinutes < 0) buf.write('(${-extraMinutes}분)');
      buf.write(' 더 짧은데 ');
    } else if (ex > 20) {
      buf.write('${ex}m');
      if (extraMinutes > 0) buf.write('($extraMinutes분)');
      buf.write(' 더 걷지만 ');
    } else {
      buf.write('거리는 거의 같지만 ');
    }
    final gains = <String>[
      if (extraLights > 0) '보안등 $extraLights개',
      if (extraCctvs > 0) 'CCTV $extraCctvs대',
      if (extraBells > 0) '비상벨 $extraBells개',
    ];
    final clauses = <String>[
      if (gains.isNotEmpty) '${gains.join(', ')}를 더 지나',
      // ↑ 개·대로 끝나므로 조사는 항상 '를'
      if (darkAvoided > 0) '어두운 구간 $darkAvoided곳을 피해',
    ];
    if (clauses.isNotEmpty) {
      buf.write(clauses.join('고 '));
      buf.write(' ');
    }
    if (shorter) {
      // 더 빠르면서 밝기도 나은 길: "…안심지수도 17점 높아요."
      buf.write(scoreGain > 0 ? '안심지수도 $scoreGain점 높아요.' : '안심지수는 비슷해요.');
    } else if (scoreGain > 0) {
      buf.write('안심지수가 $scoreGain점 높은 길이에요.');
    } else {
      buf.write('안심지수는 비슷한 길이에요.');
    }
    return buf.toString();
  }
}
