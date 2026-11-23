import 'dart:async';
import 'dart:math' as math;

import 'package:ansim_core/ansim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../controllers/route_controller.dart';
import '../controllers/theme_controller.dart';
import '../data/area_safety.dart';
import '../data/safety_data.dart';
import '../services/kakao_local.dart';
import '../services/location.dart';
import '../services/night_tools.dart';
import '../services/prefs.dart';
import '../services/safe_places.dart';
import '../services/shake.dart';
import '../services/tmap_route.dart';
import '../theme.dart';
import 'app_icons.dart';
import 'guidance_widgets.dart';
import 'guide_text.dart';
import 'kit.dart';
import 'map_layers.dart';
import 'menu_sheet.dart';
import 'safety_check.dart';
import 'nearby_sheet.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'sheets.dart';
import 'sos_sheet.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  final SafetyData data;
  final ThemeController theme;
  final AppPrefs prefs;
  const HomePage({super.key, required this.data, required this.theme, required this.prefs});

  @override
  State<HomePage> createState() => _HomePageState();
}

/// 시트 높이(화면 높이 비율): 최소·처음·최대
typedef _SheetSizes = ({double min, double init, double max});

/// 내 위치 버튼: 자유 이동 → 내 위치 따라가기 → 나침반
enum _LocMode { free, follow, compass }

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final kakao = KakaoLocalService();
  final night = NightTools();
  late final RouteController rc = RouteController(
    data: widget.data,
    kakao: kakao,
    tmap: TmapService(),
    places: SafePlacesService(),
    location: LocationService(),
    voice: Voice(),
    night: night,
    prefs: widget.prefs,
  );

  final _map = MapController();
  bool _mapReady = false;

  // 타일 공급자는 한 번만 만든다(매 빌드마다 새로 만들면 타일을 다시 불러와 끊김)
  final _osmTiles = NetworkTileProvider();
  late final _roadTiles = RoadSafetyTileProvider(widget.data.graph, widget.data.planner.router.edgeScores);

  bool _showHeat = true;
  final Set<FacilityType> _types = {...FacilityType.values};
  List<int> _facilityIdx = const [];
  Set<FacilityType> _visibleTypes = const {};

  // 누른 시설 점(이 위치에 CCTV가 있어요) + 주소
  int? _facilityHit;
  String? _facilityAddr;
  bool _facilityAddrLoading = false;
  int _facilitySeq = 0;
  Timer? _idle;

  Object? _uiKey;

  // 경로 그리기 캐시(경로·선택 탭이 바뀔 때만 다시 만든다)
  Object? _routeKey;
  List<Polyline> _routeLines = const [];
  List<SafePlace> _placesSrc = const [];
  List<SafePlace> _placePins = const [];

  Object? _sheetKey;

  /// 시트 높이 비율. 버튼 위치만 이 값으로 다시 그린다(지도는 다시 그리지 않음).
  final _sheetExtent = ValueNotifier<double>(0.3);

  // 내 위치 버튼 상태·나침반
  _LocMode _locMode = _LocMode.free;
  StreamSubscription<CompassEvent>? _compassSub;
  final _compass = ValueNotifier<double?>(null);
  DateTime _lastRotate = DateTime.fromMillisecondsSinceEpoch(0);
  List<Marker> _routeArrows = const [];

  PlanResult? _fittedPlan;
  RoutePhase _lastPhase = RoutePhase.idle;
  GeoPoint? _lastFollow;

  late final ShakeDetector _shake = ShakeDetector(onShake: _onShake);
  bool _sosOpen = false;
  bool _timerDialogOpen = false;

  // 장소 카드(검색 결과·지도 길게 누르기)
  PlaceRef? _preview;

  // 홈 시트의 '지금 내 주변' 안심 요약
  AreaSafety? _area;
  GeoPoint? _areaAt;

  SafetyData get data => widget.data;
  AppPrefs get prefs => widget.prefs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    rc.addListener(_onRouteChanged);
    prefs.addListener(_syncShake);
    night.init();
    _syncShake();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initLocation());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idle?.cancel();
    _shake.stop();
    prefs.removeListener(_syncShake);
    rc.removeListener(_onRouteChanged);
    rc.dispose();
    night.releaseAll();
    _map.dispose();
    _sheetExtent.dispose();
    _stopCompass();
    _compass.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 앱이 뒤로 가면 손전등·밝기를 돌려놓는다(배터리·주변 배려).
    if (state == AppLifecycleState.paused && rc.phase != RoutePhase.navigating) night.releaseAll();
  }

  void _syncShake() => prefs.shakeSos ? _shake.start() : _shake.stop();

  Future<void> _initLocation() async {
    final st = await rc.initLocation();
    if (!mounted) return;
    if (st != LocationStatus.ok) {
      _snack(
        st == LocationStatus.serviceOff ? '위치 서비스가 꺼져 있어요. 출발지를 검색하거나 GPS를 켜 주세요.' : '위치 권한이 없어 출발지를 검색해야 해요.',
        icon: Ic.warning,
        action: '설정',
        onAction: st == LocationStatus.serviceOff ? rc.location.openSettings : rc.location.openAppSettings,
      );
    } else if (rc.myLocation != null && !rc.myLocationInBusan) {
      _snack('현재 위치가 부산 밖이에요. 안심 경로는 부산 안에서만 계산돼요.');
    } else if (rc.myLocation != null && _mapReady) {
      _map.move(toL(rc.myLocation!), 16);
    }
  }

  void _snack(String msg, {IconData? icon, String? action, VoidCallback? onAction}) =>
      showToast(context, msg, icon: icon, action: action, onAction: onAction);

  // ── 상태 변화 → 지도 반영 ─────────────────────────────
  void _onRouteChanged() {
    if (!mounted) return;
    _refreshRouteLines();
    // 내 주변 안심 요약은 60m 넘게 움직였을 때만 다시 계산
    final here = rc.myLocation;
    if (here != null && rc.myLocationInBusan && (_areaAt == null || distanceM(_areaAt!, here) > 60)) {
      _areaAt = here;
      _area = AreaSafety.at(data, here);
    }
    if (rc.phase != RoutePhase.idle) _preview = null;
    // GPS가 움직일 때마다 화면 전체를 다시 그리지 않도록: 화면 구조가 바뀔 때만 setState.
    // (내 위치 점·남은 거리는 각자 ListenableBuilder로 따로 갱신)
    final uiKey = (
      rc.phase,
      identityHashCode(rc.plan),
      rc.safeSelected,
      rc.error,
      identityHashCode(rc.safePlaces),
      rc.notice,
      rc.originLabel,
      rc.destination?.name,
      rc.myLocation == null,
      identityHashCode(_area),
      rc.myAreaName,
    );
    if (uiKey != _uiKey) {
      _uiKey = uiKey;
      setState(() {});
    }
    final plan = rc.plan;
    if (plan != null && plan != _fittedPlan && rc.phase == RoutePhase.ready) {
      _fittedPlan = plan;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitPlan(plan));
    }
    _followIfNavigating();
    if (rc.phase != _lastPhase) {
      if (rc.phase != RoutePhase.navigating && _lastPhase == RoutePhase.navigating) night.releaseAll();
      if (rc.phase == RoutePhase.navigating && _mapReady && rc.myLocation != null) {
        _map.move(toL(rc.myLocation!), 17);
      }
      _lastPhase = rc.phase;
      _scheduleLayers();
    }
    if (rc.timerDue && !_timerDialogOpen) _showTimerCheck();
  }

  void _refreshRouteLines() {
    if (!identical(rc.safePlaces, _placesSrc)) {
      _placesSrc = rc.safePlaces;
      _placePins = spacedForMap(rc.safePlaces);
    }
    final plan = rc.plan;
    final key = plan == null ? null : (identityHashCode(plan), rc.safeSelected);
    if (key == _routeKey) return;
    _routeKey = key;
    if (plan == null) {
      _routeLines = const [];
      _routeArrows = const [];
      return;
    }
    final sel = rc.activeRoute!;
    final other = plan.comparison.identical ? null : (rc.safeSelected ? plan.general : plan.safe);
    _routeLines = [
      if (other != null)
        Polyline(
          points: other.points.map(toL).toList(),
          strokeWidth: 5,
          color: AppColors.plain.withValues(alpha: 0.9),
          borderStrokeWidth: 1.5,
          borderColor: const Color(0x88000000),
        ),
      ...routeConnectors(sel),
      ...routeCasing(sel, width: 8),
      ...coloredRoute(sel, width: 8),
    ];
    _routeArrows = routeArrows(sel);
  }

  void _fitPlan(PlanResult plan) {
    if (!_mapReady || !mounted) return;
    final h = MediaQuery.sizeOf(context).height;
    final pts = [...plan.general.points, ...plan.safe.points].map(toL).toList();
    _map.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(pts),
      padding: EdgeInsets.fromLTRB(40, 150, 60, h * 0.42 + 24),
      maxZoom: 17,
    ));
    _scheduleLayers();
  }

  void _followIfNavigating() {
    final here = rc.myLocation;
    final following = rc.phase == RoutePhase.navigating || _locMode != _LocMode.free;
    if (!_mapReady || here == null || !following) return;
    if (_lastFollow == null || distanceM(_lastFollow!, here) > 2) {
      _lastFollow = here;
      final zoom = rc.phase == RoutePhase.navigating && _map.camera.zoom < 16 ? 17.0 : _map.camera.zoom;
      _map.move(toL(here), zoom);
    }
  }

  // ── 시설 점 ──────────────────────────────────────────
  void _scheduleLayers() {
    _idle?.cancel();
    _idle = Timer(const Duration(milliseconds: 250), _refreshFacilities);
  }

  void _refreshFacilities() {
    if (!_mapReady || !mounted) return;
    final cam = _map.camera;
    final vb = cam.visibleBounds;
    final out = <int>[];
    final plan = rc.plan;
    if (_types.isNotEmpty) {
      if (rc.phase == RoutePhase.navigating && plan != null) {
        // 안내 중에는 화면을 단순하게: 지금 걷는 경로 주변 시설만
        for (final i in rc.activeRoute!.tally.indices) {
          if (_types.contains(data.facilities.typeOf(i))) out.add(i);
        }
      } else if (cam.zoom >= 16.5) {
        // 골목 수준으로 확대했을 때만, 화면 가운데에서 가까운 순으로 최대 350개
        final c = cam.center;
        final inView = data.facilities
            .inBounds(GeoBounds(vb.south, vb.west, vb.north, vb.east))
            .where((i) => _types.contains(data.facilities.typeOf(i)))
            .toList();
        double d2(int i) {
          final dy = data.facilities.lat(i) - c.latitude, dx = data.facilities.lng(i) - c.longitude;
          return dy * dy + dx * dx;
        }

        if (inView.length > 350) inView.sort((a, b) => d2(a).compareTo(d2(b)));
        out.addAll(inView.take(350));
      } else if (cam.zoom >= 14 && plan != null) {
        // 멀리서 볼 때는 경로 주변 시설만
        for (final i in rc.activeRoute!.tally.indices) {
          if (_types.contains(data.facilities.typeOf(i))) out.add(i);
        }
      }
    }
    if (out.length != _facilityIdx.length || (out.isNotEmpty && out.first != _facilityIdx.first)) {
      setState(() {
        _facilityIdx = out;
        _visibleTypes = {for (final i in out) data.facilities.typeOf(i)};
      });
    }
  }

  // ── 사용자 동작 ──────────────────────────────────────
  Future<PlaceRef?> _search({required bool origin, String? title}) => Navigator.of(context).push<PlaceRef>(
        MaterialPageRoute(
          builder: (_) => SearchPage(
            kakao: kakao,
            prefs: prefs,
            forOrigin: origin,
            title: title,
            near: rc.myLocationInBusan ? rc.myLocation : AppConfig.defaultCenter,
            currentLocationLabel: rc.myLocationInBusan ? rc.originLabel : '현재 위치가 부산 밖이거나 확인되지 않았어요',
          ),
        ),
      );

  Future<void> _pick({required bool origin}) async {
    final res = await _search(origin: origin);
    if (res == null) return;
    if (origin) {
      rc.setOrigin(res.isCurrentLocation ? null : res);
    } else if (rc.phase == RoutePhase.idle && !res.isCurrentLocation) {
      // 네이버 지도처럼 먼저 장소 카드로 보여 주고 출발/도착을 고른다
      prefs.addRecent(res);
      _showPreview(res);
    } else {
      rc.setDestination(res);
    }
  }

  void _showPreview(PlaceRef p) {
    setState(() => _preview = p);
    if (_mapReady) {
      final h = MediaQuery.sizeOf(context).height;
      // 카드에 가리지 않게 핀을 화면 위쪽 1/3 근처로
      final z = math.max(_map.camera.zoom, 16.5);
      _map.move(toL(p.point), z, offset: Offset(0, -h * 0.12));
    }
    _scheduleLayers();
  }

  /// 지도를 길게 누르면 그 지점을 장소 카드로(주소는 카카오로 확인)
  Future<void> _onLongPress(LatLng ll) async {
    if (rc.phase != RoutePhase.idle) return;
    HapticFeedback.selectionClick();
    final pt = GeoPoint(ll.latitude, ll.longitude);
    if (!busanBounds.contains(pt.lat, pt.lng)) {
      _snack('부산 안에서만 길을 찾을 수 있어요.', icon: Ic.warning);
      return;
    }
    _showPreview(PlaceRef(name: '주소 확인 중…', point: pt, category: '지도에서 선택'));
    final p = await kakao.placeAt(pt);
    if (!mounted || _preview?.point != pt) return;
    setState(() => _preview = p);
  }

  /// 지도 탭: 시설 점 근처면 그 시설 안내, 아니면 열린 카드 닫기
  void _onMapTap(LatLng ll) {
    final hit = _hitFacility(ll);
    setState(() {
      if (hit != null) {
        _facilityHit = hit;
        _facilityAddr = null;
        _facilityAddrLoading = true;
      } else {
        _facilityHit = null;
        _preview = null;
      }
    });
    if (hit != null) _loadFacilityAddr(hit);
  }

  /// 손가락 크기(약 24px) 안에서 가장 가까운 보이는 시설 점
  int? _hitFacility(LatLng ll) {
    if (_facilityIdx.isEmpty || !_mapReady) return null;
    final mpp = 156543.03392 * math.cos(ll.latitude * math.pi / 180) / math.pow(2, _map.camera.zoom);
    var bestD = 24 * mpp;
    int? best;
    final f = data.facilities;
    for (final i in _facilityIdx) {
      final d = haversineM(ll.latitude, ll.longitude, f.lat(i), f.lng(i));
      if (d <= bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  /// 앱 도로망에서 가장 가까운 도로 이름(30m 안)
  String? _roadNear(int i) {
    final f = data.facilities;
    final e = data.graph.nearestEdge(f.lat(i), f.lng(i), maxM: 30).edge;
    return e < 0 ? null : data.graph.nameOf(e);
  }

  Future<void> _loadFacilityAddr(int i) async {
    final seq = ++_facilitySeq;
    final f = data.facilities;
    final a = await kakao.addressNear(GeoPoint(f.lat(i), f.lng(i)));
    if (!mounted || seq != _facilitySeq) return;
    setState(() {
      _facilityAddr = a;
      _facilityAddrLoading = false;
    });
  }

  void _previewAs({required bool origin}) {
    final p = _preview;
    if (p == null) return;
    setState(() => _preview = null);
    if (origin) {
      rc.setOrigin(p);
      _snack('출발지를 ${p.name}(으)로 정했어요. 도착지를 골라 주세요.');
      _pick(origin: false);
    } else {
      rc.setDestination(p);
    }
  }

  Future<void> _setFavorite({required bool home}) async {
    final res = await _search(origin: false, title: home ? '집 주소 검색' : '회사 주소 검색');
    if (res == null || res.isCurrentLocation) return;
    home ? await prefs.setHome(res) : await prefs.setWork(res);
    if (mounted) _snack('${home ? '집' : '회사'}을(를) ${res.name}(으)로 저장했어요.');
  }

  Future<void> _toggleTorch() async {
    final msg = await night.toggleTorch();
    if (msg != null && mounted) _snack(msg);
  }

  /// 내 위치 버튼: 1번 → 내 위치로 이동(따라가기), 2번 → 나침반 모드(내가 보는 방향이 위), 3번 → 해제.
  void _goToMe() {
    final here = rc.myLocation;
    if (here == null) {
      _initLocation();
      return;
    }
    switch (_locMode) {
      case _LocMode.free:
        _map.moveAndRotate(toL(here), _map.camera.zoom < 16 ? 16.5 : _map.camera.zoom, 0);
        setState(() => _locMode = _LocMode.follow);
      case _LocMode.follow:
        _startCompass();
        setState(() => _locMode = _LocMode.compass);
        _snack('나침반 모드: 폰을 든 방향이 지도 위쪽이에요.');
      case _LocMode.compass:
        _stopCompass();
        _map.rotate(0);
        setState(() => _locMode = _LocMode.free);
    }
    _scheduleLayers();
  }

  void _startCompass() {
    _compassSub ??= FlutterCompass.events?.listen((e) {
      final h = e.heading;
      if (h == null || !mounted) return;
      _compass.value = h;
      if (_locMode != _LocMode.compass) return;
      // 너무 자주 돌리면 버벅이므로 80ms·2° 이상 바뀔 때만 지도 회전
      final now = DateTime.now();
      final diff = ((-h - _map.camera.rotation + 540) % 360) - 180;
      if (now.difference(_lastRotate).inMilliseconds < 80 || diff.abs() < 2) return;
      _lastRotate = now;
      final here = rc.myLocation;
      here == null ? _map.rotate(-h) : _map.moveAndRotate(toL(here), _map.camera.zoom, -h);
    });
  }

  void _stopCompass() {
    _compassSub?.cancel();
    _compassSub = null;
    _compass.value = null;
  }

  Future<void> _openSos() async {
    if (_sosOpen) return;
    _sosOpen = true;
    await showSosSheet(context, rc.myLocation, guardianPhone: prefs.guardianPhone);
    _sosOpen = false;
  }

  void _onShake() {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    _openSos();
  }

  Future<void> _showTimerCheck() async {
    _timerDialogOpen = true;
    final res = await showSafetyCheck(context);
    _timerDialogOpen = false;
    if (!mounted) return;
    switch (res) {
      case SafetyCheckResult.ok:
        rc.extendTimer(10);
        _snack('안심 타이머를 10분 연장했어요.');
      case SafetyCheckResult.help:
        rc.dismissTimerDue();
        _openSos();
      case SafetyCheckResult.noResponse:
        rc.dismissTimerDue();
        await sendEmergencySms(rc.myLocation, guardianPhone: prefs.guardianPhone);
    }
  }

  /// ☰ → 설정 화면(다크/라이트, 안전 기능, 즐겨찾기, 정보)
  void _openSettings() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SettingsPage(
          prefs: prefs,
          theme: widget.theme,
          data: data,
          onSetHome: () => _setFavorite(home: true),
          onSetWork: () => _setFavorite(home: false),
        ),
      ));

  /// 레이어 버튼 → 지도 표시(도로 밝기·시설)
  void _openLayers() => showLayerSheet(
        context,
        showHeat: _showHeat,
        types: _types,
        onChanged: (heat, types) {
          setState(() {
            _showHeat = heat;
            _types
              ..clear()
              ..addAll(types);
          });
          _scheduleLayers();
        },
      );

  // ── 화면 ─────────────────────────────────────────────
  _SheetSizes _sizes(RoutePhase p) => switch (p) {
        RoutePhase.idle => (min: 0.12, init: 0.3, max: 0.72),
        RoutePhase.planning => (min: 0.12, init: 0.13, max: 0.13),
        RoutePhase.ready => (min: 0.22, init: 0.42, max: 0.9),
        RoutePhase.navigating => (min: 0.15, init: 0.27, max: 0.45),
        RoutePhase.arrived => (min: 0.2, init: 0.31, max: 0.31),
      };

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final previewing = rc.phase == RoutePhase.idle && _preview != null;
    final sizes = previewing ? (min: 0.24, init: 0.4, max: 0.52) : _sizes(rc.phase);
    // 시트가 바뀌면(홈↔장소 카드↔경로) 버튼·범례 위치도 새 시트 높이로 맞춘다
    final sheetKey = (rc.phase, previewing);
    if (sheetKey != _sheetKey) {
      _sheetKey = sheetKey;
      final init = sizes.init;
      WidgetsBinding.instance.addPostFrameCallback((_) => _sheetExtent.value = init);
    }
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(builder: (context, box) {
        final h = box.maxHeight;
        return Stack(children: [
          Positioned.fill(child: _buildMap(dark)),
          // 상단: 검색바 / 경로 헤더 / 안내 배너
          Positioned(left: 0, right: 0, top: 0, child: SafeArea(bottom: false, child: _topBar())),
          // 시트 높이에 맞춰 움직이는 버튼들
          ValueListenableBuilder<double>(
            valueListenable: _sheetExtent,
            builder: (context, ext, _) {
              // 시트를 크게 올리면 버튼이 상단 헤더와 겹치므로 서서히 숨긴다
              final fade = ((0.72 - ext) / 0.12).clamp(0.0, 1.0);
              return Positioned(
                left: 12,
                right: 12,
                bottom: ext * h + 10,
                child: IgnorePointer(
                  ignoring: fade < 0.5,
                  child: Opacity(opacity: fade, child: _floatingButtons()),
                ),
              );
            },
          ),
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (n) {
              _sheetExtent.value = n.extent;
              return false;
            },
            child: DraggableScrollableSheet(
              key: ValueKey((rc.phase, previewing)),
              minChildSize: sizes.min,
              initialChildSize: sizes.init,
              maxChildSize: sizes.max,
              snap: true,
              builder: (context, scroll) => DecoratedBox(
                decoration: BoxDecoration(
                  color: Pal.of(context).surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                  boxShadow: const [BoxShadow(blurRadius: 24, color: Color(0x2E000000), offset: Offset(0, -2))],
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                  child: _sheetBody(scroll),
                ),
              ),
            ),
          ),
        ]);
      }),
    );
  }

  Widget _buildMap(bool dark) {
    final start = rc.myLocationInBusan ? rc.myLocation! : AppConfig.defaultCenter;
    final plan = rc.plan;
    final f = data.facilities;
    final base = TileLayer(
      urlTemplate: osmTileUrl,
      userAgentPackageName: appPackageName,
      tileProvider: _osmTiles,
      maxNativeZoom: 19,
      keepBuffer: 3,
    );
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: toL(start),
        initialZoom: 15.5,
        minZoom: 10,
        maxZoom: 19,
        backgroundColor: dark ? AppColors.night : const Color(0xFFF2F1EA),
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        onMapReady: () {
          _mapReady = true;
          if (rc.myLocationInBusan) _map.move(toL(rc.myLocation!), 16);
          if (rc.plan != null && rc.phase == RoutePhase.ready) _fitPlan(rc.plan!);
          _scheduleLayers();
        },
        onLongPress: (_, ll) => _onLongPress(ll),
        onTap: (_, ll) => _onMapTap(ll),
        onPositionChanged: (_, gesture) {
          // 손으로 지도를 움직이면 따라가기·나침반 모드를 풀어 준다(지도 앱과 같은 동작)
          if (gesture && _locMode != _LocMode.free && rc.phase != RoutePhase.navigating) {
            _stopCompass();
            setState(() => _locMode = _LocMode.free);
          }
          _scheduleLayers();
        },
      ),
      children: [
        // 야간 필터는 타일 레이어 전체에 한 번만
        ColorFiltered(colorFilter: dark ? nightTileFilter : dayTileFilter, child: base),
        if (_showHeat)
          TileLayer(
            tileProvider: _roadTiles,
            minZoom: 14,
            maxNativeZoom: 18,
            maxZoom: 19,
            keepBuffer: 3,
          ),
        if (_facilityIdx.isNotEmpty)
          CircleLayer(circles: [
            for (final i in _facilityIdx)
              CircleMarker(
                point: LatLng(f.lat(i), f.lng(i)),
                radius: 5,
                color: facilityColor(f.typeOf(i)),
                borderStrokeWidth: 1.2,
                borderColor: const Color(0xCC0C1411),
              ),
          ]),
        // 누른 시설 점 강조(고리)
        if (_facilityHit != null)
          CircleLayer(circles: [
            CircleMarker(
              point: LatLng(f.lat(_facilityHit!), f.lng(_facilityHit!)),
              radius: 13,
              color: facilityColor(f.typeOf(_facilityHit!)).withValues(alpha: 0.25),
              borderStrokeWidth: 2.5,
              borderColor: facilityColor(f.typeOf(_facilityHit!)),
            ),
          ]),
        if (_routeLines.isNotEmpty) PolylineLayer(polylines: _routeLines),
        if (_routeArrows.isNotEmpty) MarkerLayer(markers: _routeArrows),
        if (plan != null && _placePins.isNotEmpty)
          MarkerLayer(markers: [
            for (final p in _placePins) Marker(point: toL(p.point), width: 24, height: 24, rotate: true, child: SafePlacePin(p.kind)),
          ]),
        if (plan != null)
          MarkerLayer(markers: [
            Marker(
              point: toL(plan.from),
              width: 60,
              height: 34,
              rotate: true,
              alignment: Alignment.topCenter,
              child: const PlacePin(color: AppColors.leafDeep, label: '출발'),
            ),
            Marker(
              point: toL(plan.to),
              width: 60,
              height: 34,
              rotate: true,
              alignment: Alignment.topCenter,
              child: const PlacePin(color: AppColors.lamp, fg: AppColors.onLamp, label: '도착'),
            ),
          ]),
        if (_preview != null && rc.phase == RoutePhase.idle)
          MarkerLayer(markers: [
            Marker(
              point: toL(_preview!.point),
              width: 34,
              height: 44,
              rotate: true,
              alignment: Alignment.topCenter,
              child: const PreviewPin(),
            ),
          ]),
        // 안내 중: 다음 회전 지점 표시
        if (rc.phase == RoutePhase.navigating)
          ListenableBuilder(
            listenable: rc,
            builder: (_, _) {
              final m = rc.nextManeuver;
              if (m == null || m.turn == TurnKind.arrive) return const SizedBox.shrink();
              return MarkerLayer(markers: [
                Marker(point: toL(m.point), width: 30, height: 30, rotate: true, child: _TurnDot(m)),
              ]);
            },
          ),
        // 내 위치 점만 GPS마다 다시 그린다
        ListenableBuilder(
          listenable: Listenable.merge([rc, _compass]),
          builder: (_, _) => rc.myLocation == null
              ? const SizedBox.shrink()
              : MarkerLayer(markers: [
                  // 나침반이 켜져 있으면 폰이 향한 방향, 아니면 GPS 진행 방향
                  Marker(
                    point: toL(rc.myLocation!),
                    width: 44,
                    height: 44,
                    child: MyLocationDot(heading: _compass.value ?? rc.heading),
                  ),
                ]),
        ),
      ],
    );
  }

  /// 집으로 · 편의점 · 지구대·파출소 · 약국 · 응급실
  Widget _categoryChips() => ListenableBuilder(
        listenable: prefs,
        builder: (_, _) => SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 2),
            children: [
              if (prefs.home != null)
                _CategoryChip(
                  icon: Ic.home,
                  color: AppColors.leafDeep,
                  label: '집으로',
                  onTap: () => rc.setDestination(prefs.home!),
                ),
              for (final k in SafePlaceKind.values)
                _CategoryChip(icon: safeKindIcon(k), color: safeKindColor(k), label: k.label, onTap: () => _openNearby(k)),
            ],
          ),
        ),
      );

  void _openNearby(SafePlaceKind kind) {
    // 현위치가 있으면 현위치, 없으면 지금 보고 있는 지도 가운데 기준
    final c = rc.myLocationInBusan
        ? rc.myLocation!
        : (_mapReady ? GeoPoint(_map.camera.center.latitude, _map.camera.center.longitude) : AppConfig.defaultCenter);
    showNearbySheet(context, service: rc.places, center: c, kind: kind, onGo: rc.setDestination);
  }

  // ── 상단 ─────────────────────────────────────────────
  Widget _topBar() {
    final Widget bar = switch (rc.phase) {
      RoutePhase.idle => _SearchBar(onTap: () => _pick(origin: false), onMenu: _openSettings),
      RoutePhase.navigating => ListenableBuilder(
          listenable: rc,
          builder: (_, _) => TurnCard(
            next: rc.nextManeuver,
            distM: rc.nextDistM,
            then: rc.afterNext,
            destName: rc.destination?.name ?? GuideText.of(rc.lang).destFallback,
            lang: rc.lang,
          ),
        ),
      _ => _RouteHeader(
          origin: rc.originLabel,
          dest: rc.destination?.name ?? '',
          onBack: rc.clear,
          onOrigin: () => _pick(origin: true),
          onDest: () => _pick(origin: false),
          onSwap: rc.swap,
        ),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: bar),
      if (rc.phase == RoutePhase.idle && _preview == null) _categoryChips(),
      if (rc.error != null && rc.phase != RoutePhase.navigating)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: _Banner(text: rc.error!),
        ),
      if (_facilityHit != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: _FacilityCard(
            type: data.facilities.typeOf(_facilityHit!),
            count: data.facilities.weights[_facilityHit!],
            road: _roadNear(_facilityHit!),
            address: _facilityAddr,
            loading: _facilityAddrLoading,
            onClose: () => setState(() => _facilityHit = null),
          ),
        ),
      Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 12, 0),
          child: CircleBtn(icon: Ic.layers, label: '지도 표시', size: 44, onTap: _openLayers),
        ),
      ),
    ]);
  }

  Widget _floatingButtons() {
    final p = Pal.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SosButton(onTap: _openSos),
        const SizedBox(height: 6),
        Text('© OpenStreetMap',
            style: TextStyle(fontSize: 9.5, color: p.dark ? Colors.white54 : Colors.black54, fontWeight: FontWeight.w500)),
      ]),
      // 지도 위 색이 뭔지 알려 주는 범례(지금 보이는 것만)
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: _MapLegend(roads: _showHeat, types: _visibleTypes),
          ),
        ),
      ),
      Column(mainAxisSize: MainAxisSize.min, children: [
        ListenableBuilder(
          listenable: night,
          builder: (_, _) => night.torchAvailable
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: CircleBtn(
                    icon: night.torchOn ? Ic.torchOn : Ic.torchOff,
                    label: '손전등',
                    onTap: _toggleTorch,
                    bg: night.torchOn ? AppColors.lamp : null,
                    fg: night.torchOn ? AppColors.onLamp : null,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        CircleBtn(
          icon: switch (_locMode) {
            _LocMode.free => Ic.myLocation,
            _LocMode.follow => Ic.navigate,
            _LocMode.compass => Ic.compass,
          },
          label: switch (_locMode) {
            _LocMode.free => '내 위치',
            _LocMode.follow => '나침반 모드',
            _LocMode.compass => '나침반 끄기',
          },
          onTap: _goToMe,
          bg: _locMode == _LocMode.free ? null : AppColors.leafDeep,
          fg: _locMode == _LocMode.free ? null : Colors.white,
        ),
      ]),
    ]);
  }

  Widget _sheetBody(ScrollController scroll) => switch (rc.phase) {
        RoutePhase.idle when _preview != null => PlaceSheet(
            scroll: scroll,
            place: _preview!,
            fromMeM: rc.myLocation == null ? null : distanceM(rc.myLocation!, _preview!.point),
            area: AreaSafety.at(data, _preview!.point, radiusM: 200),
            onOrigin: () => _previewAs(origin: true),
            onDestination: () => _previewAs(origin: false),
            onClose: () => setState(() => _preview = null),
          ),
        RoutePhase.idle => HomeSheet(
            scroll: scroll,
            prefs: prefs,
            facilities: data.facilities,
            area: _area,
            areaName: rc.myAreaName,
            onGo: rc.setDestination,
            onSetHome: () => _setFavorite(home: true),
            onSetWork: () => _setFavorite(home: false),
          ),
        RoutePhase.planning => PlanningSheet(scroll: scroll),
        RoutePhase.ready => RouteSheet(
            scroll: scroll,
            rc: rc,
            onStart: rc.startNavigation,
            onPlaceTap: (p) => _map.move(toL(p.point), 17.5),
          ),
        // 남은 거리·현위치 점수는 GPS마다 바뀌므로 시트만 따로 갱신
        RoutePhase.navigating => ListenableBuilder(
            listenable: rc,
            builder: (_, _) =>
                NavSheet(scroll: scroll, rc: rc, night: night, onTorch: _toggleTorch, onStop: rc.stopNavigation),
          ),
        RoutePhase.arrived => ArrivedSheet(scroll: scroll, rc: rc, onClose: rc.clear),
      };
}

// ── 상단 위젯들(자체 디자인) ───────────────────────────────────
class _SearchBar extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback onMenu;
  const _SearchBar({required this.onTap, required this.onMenu});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      height: 54,
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(18), boxShadow: p.float),
      child: Row(children: [
        // 지도 앱처럼 왼쪽 ☰(설정), 가운데 검색, 오른쪽 브랜드 표시
        CircleBtn.plain(icon: Ic.menu, label: '설정', size: 50, onTap: onMenu),
        Expanded(
          child: Pressable(
            onTap: onTap,
            overlay: false,
            scale: 0.99,
            label: '장소 검색',
            child: SizedBox(
              height: 54,
              child: Row(children: [
                Expanded(
                  child: Text('어디로 갈까요?', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500, color: p.sub)),
                ),
                const _LampMark(),
                const SizedBox(width: 16),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// 검색바 오른쪽 브랜드 표시: 노란 불빛 점 + 초록 고리
class _LampMark extends StatelessWidget {
  const _LampMark();

  @override
  Widget build(BuildContext context) => Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(colors: [AppColors.lamp, Color(0x55FFC21A), Color(0x00FFC21A)], stops: [0.32, 0.62, 1]),
          border: Border.all(color: AppColors.leaf.withValues(alpha: 0.9), width: 2),
        ),
      );
}

class _RouteHeader extends StatelessWidget {
  final String origin, dest;
  final VoidCallback onBack, onOrigin, onDest, onSwap;
  const _RouteHeader(
      {required this.origin,
      required this.dest,
      required this.onBack,
      required this.onOrigin,
      required this.onDest,
      required this.onSwap});

  // 한 줄 32 + 구분선 1 → 출발·도착 점 사이 간격도 33
  static const _rowH = 32.0;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    Widget line(String text, String hint, VoidCallback onTap, {bool strong = false}) => Pressable(
          onTap: onTap,
          overlay: false,
          scale: 0.985,
          child: SizedBox(
            height: _rowH,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                text.isEmpty ? hint : text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                  color: text.isEmpty || !strong ? p.sub : p.text,
                ),
              ),
            ),
          ),
        );
    Widget dot(Color c) => Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: p.surface, width: 1.5)),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(18), boxShadow: p.float),
      child: Row(children: [
        CircleBtn.plain(icon: Ic.back, label: '뒤로', onTap: onBack),
        // 출발(초록) ─ 도착(노랑) 연결선
        Column(mainAxisSize: MainAxisSize.min, children: [
          dot(AppColors.leaf),
          Container(width: 1.6, height: _rowH + 1 - 9 - 4, margin: const EdgeInsets.symmetric(vertical: 2), color: p.line),
          dot(AppColors.lampDeep),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            line(origin, '출발지 선택', onOrigin),
            const Hairline(),
            line(dest, '도착지 선택', onDest, strong: true),
          ]),
        ),
        CircleBtn.plain(icon: Ic.swap, label: '출발·도착 바꾸기', fg: p.sub, onTap: onSwap),
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  const _Banner({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(14),
          boxShadow: Pal.of(context).soft,
        ),
        child: Row(children: [
          const Icon(Ic.warning, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
        ]),
      );
}

/// 빨간 SOS 버튼
class _SosButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SosButton({required this.onTap});

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        scale: 0.92,
        label: '긴급 도움',
        radius: BorderRadius.circular(30),
        child: Container(
          width: 54,
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.danger,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: Pal.of(context).float,
          ),
          child: const Text('SOS', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.5)),
        ),
      );
}

/// 검색바 아래 알약 모양 카테고리 칩(지도 앱 스타일).
class _CategoryChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _CategoryChip({required this.icon, required this.color, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Pressable(
        onTap: onTap,
        scale: 0.95,
        radius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 8, 14, 8),
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(20), boxShadow: p.soft),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

/// 안내 중 지도 위 다음 회전 지점
class _TurnDot extends StatelessWidget {
  final Maneuver m;
  const _TurnDot(this.m);

  @override
  Widget build(BuildContext context) => Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.leafDeep, width: 2.5),
          boxShadow: const [BoxShadow(blurRadius: 4, color: Color(0x55000000))],
        ),
        child: ManeuverIcon(m, size: 17, color: AppColors.leafDeep),
      );
}

/// 지도 범례: 칸 두 개로 나눈다.
///  ① 도로 밝기 — 어두움→밝음 색 막대 하나  ② 시설 — 지금 지도에 보이는 점만
class _MapLegend extends StatelessWidget {
  final bool roads;
  final Set<FacilityType> types;
  const _MapLegend({required this.roads, required this.types});

  @override
  Widget build(BuildContext context) {
    if (!roads && types.isEmpty) return const SizedBox.shrink();
    final p = Pal.of(context);
    final label = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: p.sub);
    final strong = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.text);
    Widget box(Widget child) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: p.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(10),
            boxShadow: p.soft,
          ),
          child: child,
        );
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (types.isNotEmpty)
          box(Row(mainAxisSize: MainAxisSize.min, children: [
            for (final t in FacilityType.values)
              if (types.contains(t))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: facilityColor(t),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xCC0C1411), width: 1),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(_facilityName(t), style: strong),
                  ]),
                ),
          ])),
        if (roads && types.isNotEmpty) const SizedBox(height: 5),
        if (roads)
          box(Row(mainAxisSize: MainAxisSize.min, children: [
            Text('도로', style: strong),
            const SizedBox(width: 7),
            Text('어두움', style: label),
            const SizedBox(width: 5),
            Container(
              width: 46,
              height: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: const LinearGradient(colors: [AppColors.danger, AppColors.lamp, AppColors.leaf]),
              ),
            ),
            const SizedBox(width: 5),
            Text('밝음', style: label),
          ])),
      ]),
    );
  }
}

String _facilityName(FacilityType t) => switch (t) {
      FacilityType.light => '보안등',
      FacilityType.cctv => 'CCTV',
      FacilityType.bell => '비상벨',
    };

IconData _facilityIcon(FacilityType t) => switch (t) {
      FacilityType.light => Ic.light,
      FacilityType.cctv => Ic.cctv,
      FacilityType.bell => Ic.bell,
    };

/// 시설 점을 눌렀을 때: "이 위치에 CCTV가 있어요" + 개수·가까운 도로·주소
class _FacilityCard extends StatelessWidget {
  final FacilityType type;
  final int count;
  final String? road;
  final String? address;
  final bool loading;
  final VoidCallback onClose;
  const _FacilityCard({
    required this.type,
    required this.count,
    required this.road,
    required this.address,
    required this.loading,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final name = _facilityName(type);
    // 받침 있으면 '이', 없으면 '가' (CCTV는 '가')
    final josa = type == FacilityType.cctv ? '가' : '이';
    final what = switch (type) {
      FacilityType.light => '보안등 $count개',
      FacilityType.cctv => '방범 카메라 $count대',
      FacilityType.bell => '누르면 경찰·관제센터와 연결되는 비상벨',
    };
    final where = [if (road != null) '$road 옆', if (address != null) '$address 근처'];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(18), boxShadow: p.float),
      child: Row(children: [
        IconBadge(_facilityIcon(type), facilityColor(type) == AppColors.lamp ? AppColors.lampDeep : facilityColor(type), size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('이 위치에 $name$josa 있어요', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(what, style: const TextStyle(fontSize: 12, color: AppColors.textSub, fontWeight: FontWeight.w500)),
            if (where.isNotEmpty)
              Text(where.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.text.withValues(alpha: 0.8), fontWeight: FontWeight.w500))
            else if (loading)
              const Text('위치 확인 중…', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
          ]),
        ),
        CircleBtn.plain(icon: Ic.close, label: '닫기', size: 38, iconSize: 16, fg: AppColors.textSub, onTap: onClose),
      ]),
    );
  }
}
