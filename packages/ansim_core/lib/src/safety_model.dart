import 'dart:math' as math;

import 'facilities.dart';
import 'geo.dart';

/// 보행 도로 등급. 바이너리 포맷(엣지 class 바이트 하위 4비트)과 순서가 같아야 한다.
enum RoadClass {
  /// trunk·primary·secondary(+link): 대로. 도로 가로등이 있다고 가정.
  major,

  /// tertiary(+link)
  tertiary,

  /// residential·unclassified·living_street·road: 골목. 보안등 데이터가 핵심.
  minor,

  /// pedestrian: 보행자 전용 거리
  pedestrian,

  /// service: 주차장·건물 진입로
  service,

  /// footway·cycleway·corridor: 보도·산책로
  footway,

  /// path·track·bridleway: 산길·비포장
  trail,

  /// steps: 계단
  steps;

  static RoadClass fromHighway(String highway) {
    switch (highway) {
      case 'trunk':
      case 'trunk_link':
      case 'primary':
      case 'primary_link':
      case 'secondary':
      case 'secondary_link':
        return RoadClass.major;
      case 'tertiary':
      case 'tertiary_link':
        return RoadClass.tertiary;
      case 'pedestrian':
        return RoadClass.pedestrian;
      case 'service':
        return RoadClass.service;
      case 'footway':
      case 'cycleway':
      case 'corridor':
        return RoadClass.footway;
      case 'path':
      case 'track':
      case 'bridleway':
        return RoadClass.trail;
      case 'steps':
        return RoadClass.steps;
      default:
        return RoadClass.minor;
    }
  }
}

/// 엣지 class 바이트: 하위 4비트 = RoadClass, bit4 = lit=yes, bit5 = lit=no.
class RoadFlags {
  static const litYes = 0x10;
  static const litNo = 0x20;

  static int encode(RoadClass c, {bool litYes = false, bool litNo = false}) =>
      c.index | (litYes ? RoadFlags.litYes : 0) | (litNo ? RoadFlags.litNo : 0);

  static RoadClass roadClass(int b) => RoadClass.values[b & 0x0F];
  static bool isLitYes(int b) => b & litYes != 0;
  static bool isLitNo(int b) => b & litNo != 0;
}

/// 한 지점의 시설 밀집도 수준(0~1).
class FacilityLevels {
  final double light;
  final double cctv;
  final double bell;
  const FacilityLevels(this.light, this.cctv, this.bell);
  static const zero = FacilityLevels(0, 0, 0);
}

/// 안심 점수 모델.
///
/// 점수(0~1) = 0.55·조명 + 0.35·CCTV + 0.10·비상벨
///   - 조명 = max(보안등 밀집도, 도로 등급별 가로등 추정치)
///     (공공데이터 '보안등'은 폭 12m 미만 골목 위주라 대로의 도로 가로등은 등급으로 보정)
///   - 밀집도 = 1 − exp(−Σ 가중치·(1 − 거리/반경) / 포화상수)
class SafetyModel {
  final double lightRadiusM;
  final double cctvRadiusM;
  final double bellRadiusM;
  final double wLight;
  final double wCctv;
  final double wBell;

  /// 이 점수 미만이면 '어두운 구간'으로 본다.
  final double darkThreshold;

  const SafetyModel({
    this.lightRadiusM = 30,
    this.cctvRadiusM = 50,
    this.bellRadiusM = 60,
    this.wLight = 0.55,
    this.wCctv = 0.35,
    this.wBell = 0.10,
    this.darkThreshold = 0.25,
  });

  /// 도로 등급별 조명 추정치(데이터에 없는 도로 가로등 보정).
  double lightPrior(int roadFlags) {
    final c = RoadFlags.roadClass(roadFlags);
    var p = switch (c) {
      RoadClass.major => 0.85,
      RoadClass.tertiary => 0.6,
      RoadClass.pedestrian => 0.5,
      RoadClass.minor => 0.15,
      RoadClass.service => 0.1,
      RoadClass.footway => 0.1,
      RoadClass.steps => 0.1,
      RoadClass.trail => 0.0,
    };
    if (RoadFlags.isLitYes(roadFlags)) p = math.max(p, 0.9);
    if (RoadFlags.isLitNo(roadFlags)) p = math.min(p, 0.05);
    return p;
  }

  FacilityLevels levelsAt(FacilityStore store, double lat, double lng) {
    var dl = 0.0, dc = 0.0, db = 0.0;
    final maxR = math.max(lightRadiusM, math.max(cctvRadiusM, bellRadiusM));
    final mLng = metersPerDegLng(lat);
    store.index.forEachCandidate(lat, lng, maxR, (i) {
      final dx = (store.lng(i) - lng) * mLng;
      final dy = (store.lat(i) - lat) * metersPerDegLat;
      final d = math.sqrt(dx * dx + dy * dy);
      final w = math.min(store.weights[i], 3).toDouble();
      switch (store.types[i]) {
        case 0:
          if (d < lightRadiusM) dl += w * (1 - d / lightRadiusM);
        case 1:
          if (d < cctvRadiusM) dc += w * (1 - d / cctvRadiusM);
        default:
          if (d < bellRadiusM) db += w * (1 - d / bellRadiusM);
      }
    });
    return FacilityLevels(
      1 - math.exp(-dl / 0.8),
      1 - math.exp(-dc / 0.8),
      1 - math.exp(-db / 0.5),
    );
  }

  /// 조명 수준(0~1): 보안등 밀집도와 도로 등급 추정치 중 큰 값.
  double lightLevel(double facilityLight, int roadFlags) =>
      math.max(facilityLight, lightPrior(roadFlags));

  double score(double light, double cctv, double bell, int roadFlags) {
    final s = wLight * lightLevel(light, roadFlags) + wCctv * cctv + wBell * bell;
    return s > 1 ? 1 : s;
  }

  /// 안심 경로 탐색 비용 계수. alpha가 클수록 어두운 길을 강하게 피한다.
  double costFactor(double score, int roadFlags, double alpha) {
    if (alpha <= 0) return 1;
    final c = RoadFlags.roadClass(roadFlags);
    final classPenalty = switch (c) {
      RoadClass.trail => 1.5,
      RoadClass.steps => 1.2,
      _ => 1.0,
    };
    return classPenalty * (1 + alpha * (1 - score));
  }
}
