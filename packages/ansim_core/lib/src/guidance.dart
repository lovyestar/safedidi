import 'dart:math' as math;

import 'geo.dart';
import 'guide_lang.dart';
import 'road_graph.dart';

/// 회전 방향(네이버 지도 도보 안내처럼 시계 방향 표현을 함께 쓴다).
enum TurnKind {
  depart,
  straight,
  slightLeft,
  left,
  sharpLeft,
  uTurn,
  slightRight,
  right,
  sharpRight,
  arrive;

  bool get isLeft => this == slightLeft || this == left || this == sharpLeft;
  bool get isRight => this == slightRight || this == right || this == sharpRight;
  bool get isTurn => isLeft || isRight || this == uTurn;

  /// 화면 글자(짧게)
  String get label => switch (this) {
        depart => '출발',
        straight => '직진',
        slightLeft => '11시 방향',
        left => '좌회전',
        sharpLeft => '8시 방향',
        uTurn => '유턴',
        slightRight => '1시 방향',
        right => '우회전',
        sharpRight => '4시 방향',
        arrive => '목적지 도착',
      };

  /// 음성(네이버 지도 도보 안내 말투: "왼쪽 방향입니다")
  String get speech => switch (this) {
        depart => '출발합니다',
        straight => '직진입니다',
        slightLeft => '11시 방향입니다',
        left || sharpLeft => '왼쪽 방향입니다',
        uTurn => '뒤로 돌아가세요',
        slightRight => '1시 방향입니다',
        right || sharpRight => '오른쪽 방향입니다',
        arrive => '목적지입니다',
      };

  /// 진행 방향 대비 꺾는 각도(도, 오른쪽 +)로 분류.
  static TurnKind fromAngle(double deg) {
    final a = deg.abs();
    if (a < 30) return straight;
    if (a >= 155) return uTurn;
    final right = deg > 0;
    if (a < 60) return right ? slightRight : slightLeft;
    if (a < 120) return right ? TurnKind.right : left;
    return right ? sharpRight : sharpLeft;
  }
}

String featureLabel(EdgeFeature f) => switch (f) {
      EdgeFeature.crossing => '횡단보도 건너기',
      EdgeFeature.overpass => '육교 건너기',
      EdgeFeature.underpass => '지하도 이용',
      EdgeFeature.steps => '계단 이용',
      EdgeFeature.none => '',
    };

String featureSpeech(EdgeFeature f) => switch (f) {
      EdgeFeature.crossing => '횡단보도를 건너세요',
      EdgeFeature.overpass => '육교를 건너세요',
      EdgeFeature.underpass => '지하도를 이용하세요',
      EdgeFeature.steps => '계단을 이용하세요',
      EdgeFeature.none => '',
    };

/// 안내 지점 하나.
class Maneuver {
  final TurnKind turn;

  /// 이 지점부터 지나는 특별한 길(횡단보도·육교·지하도·계단). 없으면 none.
  final EdgeFeature feature;

  /// 출발점부터 경로를 따라 이 지점까지 거리(m)
  final double atM;
  final GeoPoint point;

  /// 이 지점을 지나 들어서는 도로 이름(OSM). 모르면 null.
  final String? road;

  /// 꺾는 각도(도, 오른쪽 +)
  final double angle;

  /// 도착 안내에서 목적지가 있는 쪽: -1 왼쪽, 1 오른쪽, 0 앞쪽·모름
  final int side;

  const Maneuver({
    required this.turn,
    required this.atM,
    required this.point,
    this.feature = EdgeFeature.none,
    this.road,
    this.angle = 0,
    this.side = 0,
  });

  /// '왼쪽'·'오른쪽'(도착 안내용). 앞쪽이면 null.
  String? get sideText => side < 0 ? '왼쪽' : (side > 0 ? '오른쪽' : null);

  /// 안내 카드 큰 글씨(한국어). 예: "좌회전", "횡단보도 건너기", "좌회전 후 횡단보도 건너기", "목적지는 왼쪽"
  /// 다른 언어는 [GuidePhrases.title].
  String get title => GuidePhrases.ko.title(this);

  /// 음성(한국어, 앞에 "잠시 후" 등을 붙여 쓴다). 예: "왼쪽 방향입니다", "왼쪽 방향, 횡단보도를 건너세요"
  String get speech => GuidePhrases.ko.speech(this);

  Maneuver copyWith({TurnKind? turn, EdgeFeature? feature, String? road}) => Maneuver(
        turn: turn ?? this.turn,
        feature: feature ?? this.feature,
        atM: atM,
        point: point,
        road: road ?? this.road,
        angle: angle,
        side: side,
      );

  @override
  String toString() => 'Maneuver(${atM.round()}m $title${road == null ? '' : ' · $road'})';
}

/// 경로 폴리라인 → 회전·횡단보도 안내 목록(출발·도착 포함).
///
/// - 교차로(길이 3갈래 이상 만나는 노드)에서 30° 넘게 꺾이면 안내한다.
///   교차로가 아니어도 60° 넘게 꺾이면 안내한다(골목 모퉁이).
/// - 꺾는 각도는 앞뒤 [lookM]m 떨어진 점으로 재서 짧은 지그재그를 무시한다.
/// - 횡단보도·육교·지하도·계단에 들어서는 지점도 안내 지점이 된다.
///   회전과 같은 곳이면 하나로 합친다("좌회전 후 횡단보도 건너기").
/// - [roadEndM]: 도착점을 도로에 잇는 연결선이 시작되는 거리. 주면 도로를 벗어나는 그 지점을
///   도착 안내로 삼고, 연결선으로 꺾는 회전 대신 "목적지는 왼쪽"처럼 목적지 방향을 알려준다(네이버 지도 방식).
List<Maneuver> buildManeuvers(List<GeoPoint> route, RoadGraph graph, {double lookM = 12, double? roadEndM}) {
  final pts = _dedupe(route);
  if (pts.length < 2) return const [];
  final n = pts.length;
  final cum = List<double>.filled(n, 0);
  for (var i = 1; i < n; i++) {
    cum[i] = cum[i - 1] + distanceM(pts[i - 1], pts[i]);
  }
  final total = cum[n - 1];

  // 각 점의 그래프 노드(교차로 판단), 각 구간의 그래프 엣지(이름·특징)
  final node = [for (final p in pts) graph.nearestNode(p.lat, p.lng, maxM: 8)];
  final seg = List<int>.filled(n - 1, -1);
  for (var i = 0; i < n - 1; i++) {
    seg[i] = _edgeBetween(graph, node[i], node[i + 1]);
    if (seg[i] < 0) {
      final m = _mid(pts[i], pts[i + 1]);
      seg[i] = graph.nearestEdge(m.lat, m.lng, maxM: 6).edge;
    }
  }
  EdgeFeature featureAt(int i) => seg[i] < 0 ? EdgeFeature.none : graph.featureOf(seg[i]);
  String? nameAt(int i) => seg[i] < 0 ? null : graph.nameOf(seg[i]);

  // 지점 i 이후 [aheadM] 안에서 처음 나오는 도로 이름
  String? roadAfter(int i, {double aheadM = 60}) {
    for (var j = i; j < n - 1 && cum[j] - cum[i] <= aheadM; j++) {
      final s = nameAt(j);
      if (s != null) return s;
    }
    return null;
  }

  GeoPoint pointAt(double m) {
    m = m.clamp(0, total).toDouble();
    var i = 1;
    while (i < n - 1 && cum[i] < m) {
      i++;
    }
    final segLen = cum[i] - cum[i - 1];
    final t = segLen <= 0 ? 0.0 : (m - cum[i - 1]) / segLen;
    return GeoPoint(
      pts[i - 1].lat + (pts[i].lat - pts[i - 1].lat) * t,
      pts[i - 1].lng + (pts[i].lng - pts[i - 1].lng) * t,
    );
  }

  final out = <Maneuver>[
    Maneuver(turn: TurnKind.depart, atM: 0, point: pts.first, road: roadAfter(0), feature: featureAt(0)),
  ];

  for (var i = 1; i < n - 1; i++) {
    final inB = bearingDeg(pointAt(cum[i] - lookM), pts[i]);
    final outB = bearingDeg(pts[i], pointAt(cum[i] + lookM));
    final angle = _norm(outB - inB);
    final crossroads = node[i] >= 0 && graph.degree(node[i]) >= 3;
    var turn = TurnKind.fromAngle(angle);
    if (turn.isTurn && !crossroads && angle.abs() < 60) turn = TurnKind.straight;
    // 같은 이름의 길을 계속 따라가면 살짝 휘는 건 안내하지 않는다(교차로의 도로 모양 때문)
    if (turn == TurnKind.slightLeft || turn == TurnKind.slightRight) {
      final before = nameAt(i - 1), after = nameAt(i);
      if (before != null && before == after) turn = TurnKind.straight;
    }

    final f = featureAt(i);
    final entering = f != EdgeFeature.none && f != featureAt(i - 1);
    if (!turn.isTurn && !entering) continue;
    out.add(Maneuver(
      turn: turn.isTurn ? turn : TurnKind.straight,
      feature: entering ? f : EdgeFeature.none,
      atM: cum[i],
      point: pts[i],
      road: roadAfter(i),
      angle: angle,
    ));
  }
  // 도착: 연결선이 있으면 도로를 벗어나는 곳에서, 목적지가 진행 방향 어느 쪽인지 함께 안내
  final endM = roadEndM != null && roadEndM > 1 && total - roadEndM >= 3 ? roadEndM : null;
  if (endM == null) {
    out.add(Maneuver(turn: TurnKind.arrive, atM: total, point: pts.last));
  } else {
    final at = pointAt(endM);
    final a = _norm(bearingDeg(at, pts.last) - bearingDeg(pointAt(endM - lookM), at));
    final side = a <= -30 && a >= -150 ? -1 : (a >= 30 && a <= 150 ? 1 : 0);
    out.add(Maneuver(turn: TurnKind.arrive, atM: endM, point: at, side: side));
  }
  // 출발 직후·도착 직전의 회전은 위치를 도로에 붙이면서 생기는 것이라 뺀다(횡단보도 등은 남김).
  // 연결선을 알면 연결선으로 꺾는 회전만, 모르면 도착 25m 안의 회전을 뺀다.
  // 출발 직후 회전을 빼면 그 회전으로 들어선 길이 실제 출발 도로다.
  String? departRoad = out.first.road;
  out.removeWhere((m) {
    if (m.turn == TurnKind.depart || m.turn == TurnKind.arrive) return false;
    if (endM != null && m.atM > endM) return true; // 연결선(도로 밖) 위의 안내
    if (m.feature != EdgeFeature.none) return false;
    final early = m.atM < 20, late = endM != null ? m.atM > endM - 8 : total - m.atM < 25;
    if (early && m.road != null) departRoad = m.road;
    return early || late;
  });
  out[0] = out[0].copyWith(road: departRoad);
  return _merge(out);
}

/// 8m 안에 붙은 안내는 하나로(큰 회전·특징을 남긴다).
List<Maneuver> _merge(List<Maneuver> list) {
  final out = <Maneuver>[];
  for (final m in list) {
    if (out.isNotEmpty && m.turn != TurnKind.arrive && out.last.turn != TurnKind.depart && m.atM - out.last.atM < 8) {
      final prev = out.removeLast();
      final turn = m.angle.abs() > prev.angle.abs() ? m.turn : prev.turn;
      final feature = prev.feature != EdgeFeature.none ? prev.feature : m.feature;
      out.add(Maneuver(
        turn: turn,
        feature: feature,
        atM: prev.atM,
        point: prev.point,
        road: m.road ?? prev.road,
        angle: m.angle.abs() > prev.angle.abs() ? m.angle : prev.angle,
      ));
      continue;
    }
    out.add(m);
  }
  return out;
}

List<GeoPoint> _dedupe(List<GeoPoint> pts) {
  final out = <GeoPoint>[];
  for (final p in pts) {
    if (out.isEmpty || distanceM(out.last, p) > 0.5) out.add(p);
  }
  return out;
}

int _edgeBetween(RoadGraph g, int u, int v) {
  if (u < 0 || v < 0) return -1;
  for (var e = g.offsets[u]; e < g.offsets[u + 1]; e++) {
    if (g.targets[e] == v) return e;
  }
  return -1;
}

GeoPoint _mid(GeoPoint a, GeoPoint b) => GeoPoint((a.lat + b.lat) / 2, (a.lng + b.lng) / 2);

double _norm(double d) {
  var x = d % 360;
  if (x > 180) x -= 360;
  if (x <= -180) x += 360;
  return x;
}

/// a→b 방위각(진북 기준 시계 방향, 도)
double bearingDeg(GeoPoint a, GeoPoint b) {
  final dy = (b.lat - a.lat) * metersPerDegLat;
  final dx = (b.lng - a.lng) * metersPerDegLng(a.lat);
  return math.atan2(dx, dy) * 180 / math.pi;
}

/// 길 안내 진행 상태: 현재 위치(경로 위 거리)에서 다음 안내와 거리.
class GuidanceCursor {
  final List<Maneuver> maneuvers;
  GuidanceCursor(this.maneuvers);

  /// [alongM] 다음에 오는 첫 안내(출발 제외). 지나간 지 3m 안이면 아직 그 안내로 본다.
  int nextIndex(double alongM) {
    for (var i = 1; i < maneuvers.length; i++) {
      if (maneuvers[i].atM > alongM - 3) return i;
    }
    return maneuvers.length - 1;
  }
}
