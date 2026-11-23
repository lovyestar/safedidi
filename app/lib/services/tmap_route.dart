import 'dart:convert';

import 'package:ansim_core/ansim_core.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// TMAP 실패 이유를 사람이 읽을 수 있게.
class TmapException implements Exception {
  final int status;
  final String reason;
  const TmapException(this.status, this.reason);

  factory TmapException.fromResponse(int status, String body) {
    var code = '';
    try {
      final err = (jsonDecode(body) as Map)['error'] as Map?;
      code = '${err?['code'] ?? err?['errorCode'] ?? ''}';
    } catch (_) {}
    final reason = switch ((status, code)) {
      (403, 'INVALID_API_KEY') || (401, _) => '키 인증 실패 — SK open API 프로젝트에 TMAP 상품이 추가됐는지, 키가 맞는지 확인',
      (429, _) || (_, 'QUOTA_EXCEEDED') => '하루 사용량 초과',
      (400, _) => '요청 오류(출발·도착이 너무 가깝거나 경로 없음)',
      _ => '서버 응답 $status${code.isEmpty ? '' : ' $code'}',
    };
    return TmapException(status, reason);
  }

  @override
  String toString() => 'TMAP $reason';
}

class TmapRoute {
  final List<GeoPoint> points;
  final int? distanceM;
  final int? timeSec;
  const TmapRoute(this.points, this.distanceM, this.timeSec);
}

/// TMAP 보행자 경로 API — '일반 경로'(빠른 베이스라인).
class TmapService {
  final http.Client _client;
  TmapService([http.Client? client]) : _client = client ?? http.Client();

  bool get enabled => AppConfig.hasTmap;

  Future<TmapRoute> pedestrian(GeoPoint from, GeoPoint to,
      {String startName = '출발', String endName = '도착'}) async {
    final uri = Uri.https('apis.openapi.sk.com', '/tmap/routes/pedestrian', {'version': '1'});
    final res = await _client
        .post(
          uri,
          headers: {
            'appKey': AppConfig.tmapAppKey,
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'startX': from.lng.toString(),
            'startY': from.lat.toString(),
            'endX': to.lng.toString(),
            'endY': to.lat.toString(),
            'startName': Uri.encodeComponent(startName),
            'endName': Uri.encodeComponent(endName),
            'reqCoordType': 'WGS84GEO',
            'resCoordType': 'WGS84GEO',
            'searchOption': '0',
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      throw TmapException.fromResponse(res.statusCode, utf8.decode(res.bodyBytes, allowMalformed: true));
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final features = (body['features'] as List? ?? const []).cast<Map<String, dynamic>>();
    final pts = <GeoPoint>[];
    int? dist, time;
    for (final f in features) {
      final props = (f['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
      dist ??= (props['totalDistance'] as num?)?.toInt();
      time ??= (props['totalTime'] as num?)?.toInt();
      final geom = (f['geometry'] as Map?)?.cast<String, dynamic>();
      if (geom == null || geom['type'] != 'LineString') continue;
      for (final c in (geom['coordinates'] as List).cast<List>()) {
        final p = GeoPoint((c[1] as num).toDouble(), (c[0] as num).toDouble());
        if (pts.isEmpty || pts.last != p) pts.add(p);
      }
    }
    if (pts.length < 2) throw Exception('TMAP 경로가 비어 있어요');
    return TmapRoute(pts, dist, time);
  }
}
