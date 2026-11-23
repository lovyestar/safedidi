import 'dart:async';

import 'package:ansim_core/ansim_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../data/safety_data.dart';
import '../services/kakao_local.dart';
import '../services/location.dart';
import '../services/night_tools.dart';
import '../services/prefs.dart';
import '../services/safe_places.dart';
import '../services/tmap_route.dart';

enum RoutePhase { idle, planning, ready, navigating, arrived }

/// 출발·도착 → 경로 계산 → 실시간 안내(이탈 시 현위치에서 재탐색)·안심 타이머를 관리한다.
class RouteController extends ChangeNotifier {
  final SafetyData data;
  final KakaoLocalService kakao;
  final TmapService tmap;
  final SafePlacesService places;
  final LocationService location;
  final Voice voice;
  final NightTools night;
  final AppPrefs prefs;

  RouteController({
    required this.data,
    required this.kakao,
    required this.tmap,
    required this.places,
    required this.location,
    required this.voice,
    required this.night,
    required this.prefs,
  });

  /// null이면 '현위치' 출발.
  PlaceRef? origin;
  PlaceRef? destination;
  GeoPoint? myLocation;
  String? myAreaName;
  double? heading;

  PlanResult? plan;
  RoutePhase phase = RoutePhase.idle;
  String? error;

  /// 정보성 안내(예: TMAP 키 없음 → 내장 최단경로 사용)
  String? notice;

  /// 경로 결과 탭: true = 안심 경로, false = 일반(최단) 경로. 안내도 이 경로로 한다.
  bool safeSelected = true;

  /// 안심 경로 주변 편의점·지구대
  List<SafePlace> safePlaces = const [];

  // 안내 상태
  double? remainingM;
  int? remainingMin;
  double? hereScore;
  int rerouteCount = 0;

  /// 안내 시작·도착 시각(도착 화면의 걸린 시간)
  DateTime? navStartedAt;
  DateTime? arrivedAt;

  // 회전 안내(네이버 지도 도보 안내처럼 "잠시 후 왼쪽 방향입니다")
  final _guide = Expando<List<Maneuver>>();
  double alongM = 0;
  int nextIndex = 1;
  double? nextDistM;
  Object? _guideRoute;
  final _farSaid = <int>{};
  final _nearSaid = <int>{};

  /// 미리 안내(약 50m 전)·바로 안내(약 15m 전) 거리
  static const farAnnounceM = 50.0;
  static const nearAnnounceM = 15.0;

  // 안심 타이머
  DateTime? timerDeadline;
  bool timerDue = false;
  Timer? _timer;

  StreamSubscription<Position>? _sub;
  int _offCount = 0;
  DateTime _lastReplan = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastTmap = DateTime.fromMillisecondsSinceEpoch(0);
  int _planSeq = 0;

  static const offRouteM = 40.0;

  /// 시연용 경로 로그: 디버그 빌드이거나 --dart-define=DEMO_LOG=true 일 때만.
  static const _demoLog = kDebugMode || bool.fromEnvironment('DEMO_LOG');
  static const arriveM = 25.0;

  bool get myLocationInBusan => myLocation != null && busanBounds.contains(myLocation!.lat, myLocation!.lng);

  GeoPoint? get originPoint => origin?.point ?? (myLocationInBusan ? myLocation : null);
  String get originLabel => origin?.name ?? (myAreaName != null ? '현위치 · $myAreaName' : '현위치');

  /// 지금 안내(또는 선택) 중인 경로
  RouteMetrics? get activeRoute {
    final p = plan;
    if (p == null) return null;
    return safeSelected || p.comparison.identical ? p.safe : p.general;
  }

  /// 비교 경로 종류. 보통 최단 경로지만, TMAP 경로가 안심 경로보다 길면 최단이 아니므로 TMAP 경로.
  RouteKind get generalKind {
    final p = plan;
    if (p == null || !p.comparison.safeIsShorter) return RouteKind.shortest;
    return p.generalSource == GeneralRouteSource.tmap ? RouteKind.tmap : RouteKind.general;
  }

  /// 비교 경로 이름(한국어 화면용): '최단 경로' / 'TMAP 경로'
  String get generalName => GuidePhrases.ko.routeName(generalKind);

  /// 길 안내 언어(음성·안내 화면)
  GuideLang get lang => GuideLang.parse(prefs.guideLang);
  GuidePhrases get phrases => GuidePhrases.of(lang);

  /// 경로의 회전·횡단보도 안내 목록(처음 한 번만 계산)
  List<Maneuver> maneuversOf(RouteMetrics m) => _guide[m] ??= buildManeuvers(m.points, data.graph, roadEndM: m.roadEndM);

  List<Maneuver> get maneuvers {
    final r = activeRoute;
    return r == null ? const [] : maneuversOf(r);
  }

  Maneuver? get nextManeuver {
    final ms = maneuvers;
    return nextIndex < ms.length ? ms[nextIndex] : null;
  }

  /// 다음 안내 바로 뒤(그다음) 안내
  Maneuver? get afterNext {
    final ms = maneuvers;
    return nextIndex + 1 < ms.length ? ms[nextIndex + 1] : null;
  }

  DateTime? get eta => remainingMin == null ? null : DateTime.now().add(Duration(minutes: remainingMin!));

  // ── 위치 ─────────────────────────────────────────────
  Future<LocationStatus> initLocation() async {
    final st = await location.ensurePermission();
    if (st == LocationStatus.ok) {
      myLocation = await location.current();
      _sub ??= location.watch(distanceFilterM: 3).listen(_onPosition, onError: (_) {});
      _refreshAreaName();
    }
    notifyListeners();
    return st;
  }

  GeoPoint? _areaAt;

  /// '현위치 · 부산진구 부전2동' 동네 이름: 처음 한 번, 그 뒤로는 300m 넘게 움직이면 다시 가져온다.
  void _refreshAreaName() {
    final here = myLocation;
    if (here == null || (_areaAt != null && distanceM(_areaAt!, here) < 300)) return;
    _areaAt = here;
    kakao.shortAddress(here).then((a) {
      if (a == null) return;
      myAreaName = a;
      notifyListeners();
    });
  }

  // ── 출발·도착 ─────────────────────────────────────────
  void setOrigin(PlaceRef? p) {
    origin = p;
    if (p != null) prefs.addRecent(p);
    _maybePlan();
  }

  void setDestination(PlaceRef p) {
    destination = p;
    prefs.addRecent(p);
    _maybePlan();
  }

  void swap() {
    if (destination == null) return;
    final d = destination!;
    destination = origin ??
        (myLocation != null ? PlaceRef(name: originLabel, point: myLocation!, isCurrentLocation: true) : null);
    origin = d;
    _maybePlan();
  }

  void selectRoute({required bool safe}) {
    if (phase == RoutePhase.navigating) return;
    safeSelected = safe;
    notifyListeners();
  }

  void clear() {
    stopNavigation();
    destination = null;
    origin = null;
    plan = null;
    error = null;
    notice = null;
    safePlaces = const [];
    phase = RoutePhase.idle;
    notifyListeners();
  }

  void _maybePlan() {
    if (destination != null) {
      planRoute();
    } else {
      notifyListeners();
    }
  }

  // ── 경로 계산 ─────────────────────────────────────────
  Future<void> planRoute({bool reroute = false}) async {
    final from = originPoint, to = destination?.point;
    if (to == null) return;
    if (from == null) {
      error = myLocation == null ? '현재 위치를 알 수 없어요. 출발지를 검색해 주세요.' : '현재 위치가 부산 밖이에요. 출발지를 부산 안에서 검색해 주세요.';
      phase = RoutePhase.idle;
      notifyListeners();
      return;
    }
    final seq = ++_planSeq;
    if (!reroute) {
      phase = RoutePhase.planning;
      safeSelected = true;
    }
    error = null;
    notifyListeners();

    // 1) 일반 경로: TMAP 보행자 경로(키가 있을 때). 재탐색 땐 30초에 한 번만.
    List<GeoPoint>? general;
    String? note;
    final now = DateTime.now();
    if (tmap.enabled && (!reroute || now.difference(_lastTmap).inSeconds >= 30)) {
      try {
        _lastTmap = now;
        final r = await tmap.pedestrian(from, to, startName: origin?.name ?? '현위치', endName: destination!.name);
        general = r.points;
      } on TmapException catch (e) {
        note = 'TMAP 경로를 받지 못해 앱 내장 최단 경로와 비교했어요. (${e.reason})';
      } catch (_) {
        note = 'TMAP 경로를 받지 못해 앱 내장 최단 경로와 비교했어요. (네트워크 오류)';
      }
    } else if (!tmap.enabled) {
      note = 'TMAP 키가 없어 앱이 직접 계산한 최단 경로와 비교해요.';
    }
    if (seq != _planSeq) return; // 그새 새 요청이 들어옴

    // 2) 안심 경로: 앱 내장 A* (기기 안에서 계산)
    try {
      plan = data.planner.plan(from, to, externalGeneral: general);
      notice = note;
      if (phase != RoutePhase.navigating) phase = RoutePhase.ready;
      if (phase == RoutePhase.navigating) {
        safeSelected = true; // 재탐색 경로는 항상 안심 경로로 안내
        _updateProgress();
      }
      _debugLogRoute();
      _loadSafePlaces(seq);
    } on PlanException catch (e) {
      error = e.message;
      if (!reroute) {
        plan = null;
        phase = RoutePhase.idle;
      }
    }
    notifyListeners();
  }

  Future<void> _loadSafePlaces(int seq) async {
    final route = plan?.safe.points;
    if (route == null) return;
    try {
      final list = await places.along(route);
      if (seq != _planSeq) return;
      safePlaces = list;
      notifyListeners();
    } catch (_) {}
  }

  // ── 안내 ─────────────────────────────────────────────
  Future<void> startNavigation() async {
    final route = activeRoute;
    if (route == null) return;
    phase = RoutePhase.navigating;
    rerouteCount = 0;
    _offCount = 0;
    _guideRoute = null;
    navStartedAt = DateTime.now();
    arrivedAt = null;
    await night.keepAwake(true);
    if (location.status != LocationStatus.ok) await initLocation();
    _updateProgress(announce: false);
    _startTimer(route.minutes);
    notifyListeners();
    _debugLogRoute();
    if (_demoLog) debugPrint('ANSIM_NAV start');
    final first = nextManeuver, d = nextDistM;
    final hasFirst = first != null && d != null && first.turn != TurnKind.arrive;
    final near = hasFirst && d <= farAnnounceM;
    if (near) _farSaid.add(nextIndex);
    final road = maneuvers.isEmpty ? null : maneuvers.first.road;
    _say(phrases.start(
      kind: safeSelected ? RouteKind.safe : generalKind,
      minutes: route.minutes,
      distanceM: route.distanceM,
      score: route.safetyScore,
      first: hasFirst ? first : null,
      firstDistM: hasFirst ? d : null,
      firstRoad: road,
      firstIsNear: near,
    ));
  }

  void stopNavigation({bool arrived = false}) {
    if (phase != RoutePhase.navigating) return;
    phase = arrived ? RoutePhase.arrived : RoutePhase.ready;
    if (arrived) arrivedAt = DateTime.now();
    if (_demoLog) debugPrint('ANSIM_NAV ${arrived ? 'arrived' : 'stop'}');
    _cancelTimer();
    night.keepAwake(false);
    if (!arrived) voice.stop();
    notifyListeners();
  }

  void _onPosition(Position p) {
    myLocation = GeoPoint(p.latitude, p.longitude);
    _refreshAreaName();
    if (p.heading.isFinite && p.heading > 0) heading = p.heading;
    if (phase == RoutePhase.navigating && plan != null) {
      _updateProgress();
      final dest = destination?.point;
      if (dest != null && distanceM(myLocation!, dest) <= arriveM) {
        final ms = maneuvers;
        _say(phrases.arrived(ms.isEmpty ? 0 : ms.last.side));
        stopNavigation(arrived: true);
        return;
      }
      _checkOffRoute();
    }
    notifyListeners();
  }

  void _updateProgress({bool announce = true}) {
    final here = myLocation;
    final active = activeRoute;
    if (here == null || active == null) return;
    final prog = progressOnPolyline(active.points, here);
    remainingM = prog.remainingM;
    remainingMin = RouteAnalyzer.minutesFor(prog.remainingM);
    // 경로 위에 있으면 지금 지나는 구간 점수(지도에 칠한 선 색과 같은 값), 벗어났으면 그 자리 점수
    hereScore = (prog.offRouteM <= offRouteM ? active.scoreOfSegment(prog.segment) : null) ??
        data.raster.scoreAt(here.lat, here.lng) ??
        data.planner.analyzer.scoreAt(here.lat, here.lng);

    // 다음 안내 지점과 거리. 경로가 바뀌면(재탐색) 안내 기록을 비운다.
    alongM = prog.alongM;
    if (!identical(_guideRoute, active)) {
      _guideRoute = active;
      _farSaid.clear();
      _nearSaid.clear();
    }
    final ms = maneuversOf(active);
    if (ms.isEmpty) return;
    nextIndex = GuidanceCursor(ms).nextIndex(alongM);
    nextDistM = (ms[nextIndex].atM - alongM).clamp(0, double.infinity).toDouble();
    if (announce && phase == RoutePhase.navigating) _announce(ms, nextIndex, nextDistM!);
  }

  /// 네이버 지도 도보 안내 말투: 약 50m 전 "잠시 후 왼쪽 방향입니다, 이어서 횡단보도를 건너세요",
  /// 약 15m 전 "왼쪽 방향입니다" + 진동.
  void _announce(List<Maneuver> ms, int i, double d) {
    final m = ms[i];
    final ph = phrases;
    if (m.turn == TurnKind.arrive) {
      // 도로를 벗어나 목적지로 들어가는 곳: "잠시 후 목적지입니다. 목적지는 왼쪽에 있습니다"
      final side = m.sideText;
      if (d <= nearAnnounceM) {
        if (side != null && _nearSaid.add(i)) {
          _farSaid.add(i);
          _say(ph.speech(m));
          HapticFeedback.vibrate();
        }
      } else if (d <= farAnnounceM && (side != null || d > arriveM) && _farSaid.add(i)) {
        _say(ph.arriveSoon(m, d));
      }
      return;
    }
    // 30m 안에 바로 이어지는 안내는 "이어서"로 붙인다
    String said() {
      final now = ph.speech(m);
      if (i + 1 >= ms.length) return now;
      final nx = ms[i + 1];
      if (nx.atM - m.atM > 30) return now;
      return ph.chain(now, ph.speech(nx));
    }

    if (d <= nearAnnounceM) {
      if (_nearSaid.add(i)) {
        _farSaid.add(i);
        if (i + 1 < ms.length && ms[i + 1].atM - m.atM <= 30) _farSaid.add(i + 1);
        _say(said());
        HapticFeedback.vibrate();
      }
    } else if (d <= farAnnounceM) {
      if (_farSaid.add(i)) {
        if (i + 1 < ms.length && ms[i + 1].atM - m.atM <= 30) _farSaid.add(i + 1);
        _say(ph.soon(said(), d));
      }
    }
  }

  void _say(String text) {
    if (_demoLog) debugPrint('ANSIM_GUIDE ${alongM.round()}m $text');
    voice.locale = lang.ttsLocale;
    voice.say(text);
  }


  void _checkOffRoute() {
    final route = activeRoute?.points;
    final here = myLocation;
    if (route == null || here == null) return;
    final off = progressOnPolyline(route, here).offRouteM;
    _offCount = off > offRouteM ? _offCount + 1 : 0;
    final now = DateTime.now();
    if (_offCount >= 2 && now.difference(_lastReplan).inSeconds >= 10) {
      _lastReplan = now;
      _offCount = 0;
      origin = null; // 현위치에서 다시
      rerouteCount++;
      planRoute(reroute: true).then((_) {
        if (error == null) _say(phrases.rerouted());
      });
    }
  }

  // ── 안심 타이머 ───────────────────────────────────────
  /// 예상 소요 시간 × 1.3 + 여유 시간이 지나도 도착하지 않으면 안부를 묻는다.
  void _startTimer(int minutes) {
    _cancelTimer();
    if (!prefs.safetyTimer) return;
    final total = Duration(seconds: (minutes * 60 * 1.3).round()) + Duration(minutes: prefs.timerBufferMin);
    timerDeadline = DateTime.now().add(total);
    _timer = Timer(total, _onTimerDue);
  }

  void _onTimerDue() {
    if (phase != RoutePhase.navigating) return;
    timerDue = true;
    _say(phrases.timerDue());
    notifyListeners();
  }

  /// '괜찮아요' → 타이머 연장
  void extendTimer([int minutes = 10]) {
    timerDue = false;
    _timer?.cancel();
    final d = Duration(minutes: minutes);
    timerDeadline = DateTime.now().add(d);
    _timer = Timer(d, _onTimerDue);
    notifyListeners();
  }

  void dismissTimerDue() {
    timerDue = false;
    notifyListeners();
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
    timerDeadline = null;
    timerDue = false;
  }

  /// 디버그 빌드 전용: 현재 안내 경로를 logcat에 남긴다.
  /// tools/preprocess/bin/walk_demo.dart 가 이 경로를 따라 에뮬레이터 GPS를 움직인다.
  void _debugLogRoute() {
    final pts = activeRoute?.points;
    if (!_demoLog || pts == null) return;
    final id = DateTime.now().millisecondsSinceEpoch;
    const chunk = 40;
    final total = (pts.length / chunk).ceil();
    for (var i = 0; i < total; i++) {
      final part = pts.skip(i * chunk).take(chunk).map((p) => '${p.lat.toStringAsFixed(6)},${p.lng.toStringAsFixed(6)}').join(';');
      debugPrint('ANSIM_ROUTE $id ${i + 1}/$total $part');
    }
  }


  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}
