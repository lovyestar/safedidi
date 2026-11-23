import 'dart:convert';

import 'package:ansim_core/ansim_core.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// 출발·도착지. [isCurrentLocation]이면 point는 GPS 위치로 매번 갱신된다.
class PlaceRef {
  final String name;
  final String? address;
  final String? category;
  final GeoPoint point;
  final bool isCurrentLocation;
  final double? distanceM;

  const PlaceRef({
    required this.name,
    required this.point,
    this.address,
    this.category,
    this.isCurrentLocation = false,
    this.distanceM,
  });
}

class KakaoKeyMissing implements Exception {
  @override
  String toString() => '카카오 REST API 키가 설정되지 않았어요.';
}

/// 카카오 로컬 API: 키워드 장소 검색 + 좌표→주소.
class KakaoLocalService {
  final http.Client _client;
  KakaoLocalService([http.Client? client]) : _client = client ?? http.Client();

  static const _host = 'dapi.kakao.com';
  // 부산 범위로 검색 결과를 제한(minX,minY,maxX,maxY)
  static final _busanRect =
      '${busanBounds.minLng},${busanBounds.minLat},${busanBounds.maxLng},${busanBounds.maxLat}';

  Map<String, String> get _headers => {'Authorization': 'KakaoAK ${AppConfig.kakaoRestKey}'};

  Future<List<PlaceRef>> search(String query, {GeoPoint? near}) async {
    if (!AppConfig.hasKakao) throw KakaoKeyMissing();
    final q = query.trim();
    if (q.isEmpty) return const [];
    final uri = Uri.https(_host, '/v2/local/search/keyword.json', {
      'query': q,
      'rect': _busanRect,
      'size': '15',
      if (near != null) 'x': near.lng.toString(),
      if (near != null) 'y': near.lat.toString(),
    });
    final res = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
    if (res.statusCode == 401) throw Exception('카카오 키 인증에 실패했어요(401). REST API 키를 확인해 주세요.');
    if (res.statusCode != 200) throw Exception('장소 검색 실패 (${res.statusCode})');
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final docs = (body['documents'] as List).cast<Map<String, dynamic>>();
    return [
      for (final d in docs)
        PlaceRef(
          name: d['place_name'] as String,
          address: _nonEmpty(d['road_address_name']) ?? _nonEmpty(d['address_name']),
          category: _nonEmpty(d['category_group_name']) ?? _lastCategory(d['category_name']),
          point: GeoPoint(double.parse(d['y'] as String), double.parse(d['x'] as String)),
          distanceM: double.tryParse('${d['distance'] ?? ''}'),
        ),
    ];
  }

  /// 지도에서 길게 누른 지점 → 장소(건물 이름이 있으면 이름, 없으면 주소). 실패하면 주소 없이 좌표만.
  Future<PlaceRef> placeAt(GeoPoint p) async {
    const fallback = '지도에서 선택한 위치';
    if (!AppConfig.hasKakao) return PlaceRef(name: fallback, point: p);
    try {
      final uri = Uri.https(_host, '/v2/local/geo/coord2address.json', {'x': p.lng.toString(), 'y': p.lat.toString()});
      final res = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return PlaceRef(name: fallback, point: p);
      final docs = ((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['documents'] as List).cast<Map<String, dynamic>>();
      if (docs.isEmpty) return PlaceRef(name: fallback, point: p);
      final road = docs.first['road_address'] as Map<String, dynamic>?;
      final jibun = docs.first['address'] as Map<String, dynamic>?;
      final building = _nonEmpty(road?['building_name']);
      final roadAddr = _nonEmpty(road?['address_name']);
      final jibunAddr = _nonEmpty(jibun?['address_name']);
      return PlaceRef(
        name: building ?? roadAddr ?? jibunAddr ?? fallback,
        address: building != null ? (roadAddr ?? jibunAddr) : (roadAddr != null ? jibunAddr : null),
        category: '지도에서 선택',
        point: p,
      );
    } catch (_) {
      return PlaceRef(name: fallback, point: p);
    }
  }

  /// 좌표 → 사람이 읽는 주소(예: "부산진구 중앙대로 702"). 도로명이 없으면 지번. 실패하면 null.
  Future<String?> addressNear(GeoPoint p) async {
    if (!AppConfig.hasKakao) return null;
    try {
      final uri = Uri.https(_host, '/v2/local/geo/coord2address.json', {'x': p.lng.toString(), 'y': p.lat.toString()});
      final res = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      final docs = ((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['documents'] as List).cast<Map<String, dynamic>>();
      if (docs.isEmpty) return null;
      final road = docs.first['road_address'] as Map<String, dynamic>?;
      final jibun = docs.first['address'] as Map<String, dynamic>?;
      final s = _nonEmpty(road?['address_name']) ?? _nonEmpty(jibun?['address_name']);
      return s?.replaceFirst(RegExp(r'^부산(광역시)?\s+'), '');
    } catch (_) {
      return null;
    }
  }

  /// 좌표 → 짧은 주소(예: "부산진구 부전동"). 실패하면 null.
  Future<String?> shortAddress(GeoPoint p) async {
    if (!AppConfig.hasKakao) return null;
    try {
      final uri = Uri.https(_host, '/v2/local/geo/coord2regioncode.json',
          {'x': p.lng.toString(), 'y': p.lat.toString()});
      final res = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      final docs = ((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['documents'] as List)
          .cast<Map<String, dynamic>>();
      final h = docs.firstWhere((d) => d['region_type'] == 'H', orElse: () => docs.first);
      return '${h['region_2depth_name']} ${h['region_3depth_name']}'.trim();
    } catch (_) {
      return null;
    }
  }

  static String? _nonEmpty(Object? v) {
    final s = v?.toString().trim();
    return s == null || s.isEmpty ? null : s;
  }

  static String? _lastCategory(Object? v) {
    final s = _nonEmpty(v);
    return s?.split('>').last.trim();
  }
}
