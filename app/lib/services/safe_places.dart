import 'dart:convert';

import 'package:ansim_core/ansim_core.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

enum SafePlaceKind {
  store('편의점'),
  police('지구대·파출소'),
  pharmacy('약국'),
  emergency('응급실');

  final String label;
  const SafePlaceKind(this.label);
}

/// 주변 검색 결과(현위치 기준 거리 포함)
class NearbyPlace {
  final SafePlace place;
  final double distanceM;
  const NearbyPlace(this.place, this.distanceM);
}

class SafePlace {
  final String name;
  final SafePlaceKind kind;
  final GeoPoint point;
  final String? address;

  /// 안심 경로에서 떨어진 거리(m)
  final double fromRouteM;
  const SafePlace(this.name, this.kind, this.point, this.address, this.fromRouteM);
}

/// 카카오 장소의 카테고리(그룹 코드·분류 경로)가 이 종류에 맞는지.
/// 키워드 검색은 이름만 같아도 섞여 들어오므로(예: '응급실국물떡볶이' = 음식점) 분류 경로로 확인한다.
/// 카카오의 응급실 장소는 그룹 코드가 비어 있고 경로가 '의료,건강 > 병원 > 응급실'이라 코드만으로는 못 거른다.
bool acceptsCategory(SafePlaceKind kind, String groupCode, String categoryName) {
  final path = categoryName.split('>').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  if (path.isEmpty) return false;
  return switch (kind) {
    // 의료,건강 > 병원 > … > 응급실
    SafePlaceKind.emergency => path.first == '의료,건강' && path.contains('병원') && path.last == '응급실',
    // 사회,공공기관 > 행정기관 > 경찰서 > 지구대|파출소 (방범초소·치안센터처럼 상주 경찰이 없는 곳은 제외)
    SafePlaceKind.police =>
      path.contains('경찰서') && (path.last == '지구대' || path.last == '파출소') && (groupCode.isEmpty || groupCode == 'PO3'),
    // 가정,생활 > 편의점 > …
    SafePlaceKind.store => groupCode == 'CS2' && path.contains('편의점'),
    // 의료,건강 > 약국
    SafePlaceKind.pharmacy => groupCode == 'PM9' && path.contains('약국'),
  };
}

/// 지도 핀이 겹치지 않게: 지구대·파출소는 모두, 편의점은 [minGapM] 간격으로 솎는다.
List<SafePlace> spacedForMap(List<SafePlace> all, {double minGapM = 150}) {
  final out = <SafePlace>[...all.where((p) => p.kind == SafePlaceKind.police)];
  for (final p in all.where((p) => p.kind == SafePlaceKind.store)) {
    if (out.every((q) => distanceM(q.point, p.point) >= minGapM)) out.add(p);
  }
  return out;
}

/// 경로 주변 '위급할 때 피할 곳': 편의점, 지구대·파출소 (카카오 로컬 API).
class SafePlacesService {
  final http.Client _client;
  SafePlacesService([http.Client? client]) : _client = client ?? http.Client();

  static const maxFromRouteM = 150.0;

  Future<List<SafePlace>> along(List<GeoPoint> route) async {
    if (!AppConfig.hasKakao || route.length < 2) return const [];
    final box = GeoBounds.fromPoints(route).expandedBy(maxFromRouteM);
    final rect = '${box.minLng},${box.minLat},${box.maxLng},${box.maxLat}';
    final results = await Future.wait([
      _query('/v2/local/search/category.json', {'category_group_code': 'CS2', 'rect': rect}, SafePlaceKind.store),
      _query('/v2/local/search/keyword.json', {'query': '지구대', 'rect': rect}, SafePlaceKind.police),
      _query('/v2/local/search/keyword.json', {'query': '파출소', 'rect': rect}, SafePlaceKind.police),
    ]);
    final seen = <String>{};
    final out = <SafePlace>[];
    for (final p in results.expand((x) => x)) {
      final key = '${p.name}@${p.point.lat.toStringAsFixed(4)},${p.point.lng.toStringAsFixed(4)}';
      if (!seen.add(key)) continue;
      final d = progressOnPolyline(route, p.point).offRouteM;
      if (d > maxFromRouteM) continue;
      out.add(SafePlace(p.name, p.kind, p.point, p.address, d));
    }
    // 경찰 먼저, 그다음 경로에 가까운 순
    out.sort((a, b) => a.kind != b.kind ? b.kind.index.compareTo(a.kind.index) : a.fromRouteM.compareTo(b.fromRouteM));
    return out.take(30).toList();
  }

  /// 현위치 주변(반경 [radiusM]) 안전 장소를 가까운 순으로. 밤에 급히 피할 곳 찾기용.
  Future<List<NearbyPlace>> nearby(GeoPoint center, SafePlaceKind kind, {int radiusM = 2000}) async {
    if (!AppConfig.hasKakao) throw Exception('카카오 REST API 키가 없어 주변 검색을 할 수 없어요.');
    const cat = '/v2/local/search/category.json', kw = '/v2/local/search/keyword.json';
    final base = {'x': '${center.lng}', 'y': '${center.lat}', 'radius': '$radiusM', 'sort': 'distance'};
    final lists = await Future.wait(switch (kind) {
      SafePlaceKind.store => [_query(cat, {...base, 'category_group_code': 'CS2'}, kind)],
      SafePlaceKind.pharmacy => [_query(cat, {...base, 'category_group_code': 'PM9'}, kind)],
      SafePlaceKind.police => [
          _query(kw, {...base, 'query': '지구대'}, kind),
          _query(kw, {...base, 'query': '파출소'}, kind),
        ],
      SafePlaceKind.emergency => [_query(kw, {...base, 'query': '응급실'}, kind)],
    });
    final seen = <String>{};
    final out = <NearbyPlace>[];
    for (final p in lists.expand((x) => x)) {
      if (!seen.add('${p.name}@${p.point.lat.toStringAsFixed(4)},${p.point.lng.toStringAsFixed(4)}')) continue;
      out.add(NearbyPlace(p, distanceM(center, p.point)));
    }
    out.sort((a, b) => a.distanceM.compareTo(b.distanceM));
    return out.take(20).toList();
  }

  Future<List<SafePlace>> _query(String path, Map<String, String> params, SafePlaceKind kind) async {
    final out = <SafePlace>[];
    for (var page = 1; page <= 2; page++) {
      try {
        final uri = Uri.https('dapi.kakao.com', path, {...params, 'size': '15', 'page': '$page'});
        final res = await _client
            .get(uri, headers: {'Authorization': 'KakaoAK ${AppConfig.kakaoRestKey}'}).timeout(const Duration(seconds: 6));
        if (res.statusCode != 200) break;
        final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        for (final d in (body['documents'] as List).cast<Map<String, dynamic>>()) {
          final name = d['place_name'] as String;
          // 이름이 아니라 카카오 카테고리로 걸러낸다(예: '응급실국물떡볶이'는 음식점이라 제외)
          if (!acceptsCategory(kind, '${d['category_group_code'] ?? ''}', '${d['category_name'] ?? ''}')) continue;
          out.add(SafePlace(
            name,
            kind,
            GeoPoint(double.parse(d['y'] as String), double.parse(d['x'] as String)),
            (d['road_address_name'] as String?)?.isNotEmpty == true ? d['road_address_name'] as String : d['address_name'] as String?,
            0,
          ));
        }
        if ((body['meta'] as Map?)?['is_end'] == true) break;
      } catch (_) {
        break;
      }
    }
    return out;
  }
}
