// 안심디디 데이터 전처리.
//
// 입력(rawdata/, Git 제외):
//   lights/*.csv        부산 16개 구·군 보안등정보 (전국보안등정보표준데이터, UTF-8)
//   cctv/*.csv          부산광역시_방범용 CCTV 정보 (CP949)
//   bells/page*.json    전국안전비상벨위치표준데이터 (JSON, 부산만 추림)
//   osm/busan_walk.json OpenStreetMap 부산 보행 가능 도로 (Overpass API)
//   osm/busan_motorway.json OpenStreetMap 부산 고속도로·자동차전용도로 (차도 위 보안등 거르기용)
// 출력(app/assets/data/):
//   facilities.bin, graph.bin, meta.json
//
// 실행: cd tools/preprocess && dart run bin/preprocess.dart [--raw ../../rawdata] [--out ../../app/assets/data]

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ansim_core/ansim_core.dart';

void main(List<String> args) {
  String opt(String name, String def) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : def;
  }

  final raw = Directory(opt('--raw', '../../rawdata'));
  final out = Directory(opt('--out', '../../app/assets/data'));
  if (!raw.existsSync()) {
    stderr.writeln('rawdata 폴더가 없습니다: ${raw.path}');
    exit(1);
  }
  out.createSync(recursive: true);
  final sw = Stopwatch()..start();
  void log(String s) => stdout.writeln('[${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s] $s');

  // ── 1. 안전시설 ────────────────────────────────────────────
  final points = <_Fac>[];
  final lightStats = _readLights(Directory('${raw.path}/lights'), points);
  log('보안등: ${lightStats.rows}행 → ${lightStats.kept}건 (범위 밖/좌표 오류 ${lightStats.dropped}건, 좌표 뒤바뀜 보정 ${lightStats.swapped}건)');
  final cctvStats = _readCctv(Directory('${raw.path}/cctv'), points);
  log('CCTV: ${cctvStats.rows}행 → ${cctvStats.kept}건 (같은 지점 카메라 묶음, 제외 ${cctvStats.dropped}건)');
  final bellStats = _readBells(Directory('${raw.path}/bells'), points);
  log('비상벨: 전국 ${bellStats.rows}행 중 부산 ${bellStats.kept}건');

  final carOnly = _CarOnlyIndex.fromOsm(File('${raw.path}/osm/busan_motorway.json'));
  log('고속도로·자동차전용도로: 조각 ${carOnly.count}개');

  // ── 2. 도로망 ──────────────────────────────────────────────
  final osmFile = File('${raw.path}/osm/busan_walk.json');
  final osm = jsonDecode(osmFile.readAsStringSync()) as Map<String, dynamic>;
  final osmTime = (osm['osm3s'] as Map?)?['timestamp_osm_base'] as String? ?? '';
  final elements = (osm['elements'] as List).cast<Map<String, dynamic>>();
  final nodeLat = <int, int>{}, nodeLng = <int, int>{};
  for (final e in elements) {
    if (e['type'] == 'node') {
      nodeLat[e['id'] as int] = ((e['lat'] as num) * 1e6).round();
      nodeLng[e['id'] as int] = ((e['lon'] as num) * 1e6).round();
    }
  }
  // OSM 노드 id → 임시 인덱스
  final idx = <int, int>{};
  final tLat = <int>[], tLng = <int>[];
  int nodeIndex(int id) => idx.putIfAbsent(id, () {
        tLat.add(nodeLat[id]!);
        tLng.add(nodeLng[id]!);
        return tLat.length - 1;
      });
  final eu = <int>[], ev = <int>[], ef = <int>[], efe = <int>[];
  final en = <String?>[];
  final featureCount = <EdgeFeature, int>{};
  final seen = <int>{};
  var ways = 0, missing = 0;
  final classCount = <RoadClass, int>{};
  for (final e in elements) {
    if (e['type'] != 'way') continue;
    final tags = (e['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
    final hw = tags['highway'] as String?;
    if (hw == null) continue;
    final lit = tags['lit'] as String?;
    final cls = RoadClass.fromHighway(hw);
    final flags = RoadFlags.encode(cls,
        litYes: lit == 'yes' || lit == '24/7' || lit == 'automatic',
        litNo: lit == 'no' || lit == 'disused');
    final refs = (e['nodes'] as List).cast<int>();
    final name = tags['name'] as String?;
    var wayLen = 0.0;
    for (var i = 1; i < refs.length; i++) {
      final a = refs[i - 1], b = refs[i];
      if (nodeLat.containsKey(a) && nodeLat.containsKey(b)) {
        wayLen += haversineM(nodeLat[a]! / 1e6, nodeLng[a]! / 1e6, nodeLat[b]! / 1e6, nodeLng[b]! / 1e6);
      }
    }
    final feature = _featureOf(hw, tags, wayLen);
    featureCount[feature] = (featureCount[feature] ?? 0) + 1;
    ways++;
    classCount[cls] = (classCount[cls] ?? 0) + 1;
    for (var i = 1; i < refs.length; i++) {
      if (!nodeLat.containsKey(refs[i - 1]) || !nodeLat.containsKey(refs[i])) {
        missing++;
        continue;
      }
      final u = nodeIndex(refs[i - 1]), v = nodeIndex(refs[i]);
      if (u == v) continue;
      final key = u < v ? u * 1000000 + v : v * 1000000 + u;
      if (!seen.add(key)) continue;
      eu.add(u);
      ev.add(v);
      ef.add(flags);
      efe.add(feature.index);
      en.add(name);
    }
  }
  log('OSM: way $ways개, 노드 ${tLat.length}개, 도로 조각 ${eu.length}개 (좌표 없는 참조 $missing)');
  log('도로 등급: ${classCount.entries.map((e) => '${e.key.name} ${e.value}').join(', ')}');
  log('길 안내 특징(way): ${featureCount.entries.map((e) => '${e.key.name} ${e.value}').join(', ')}');

  // 가장 큰 연결 요소만 남긴다(섬처럼 끊긴 조각에 출발점이 붙는 것을 방지).
  final comp = _components(tLat.length, eu, ev);
  final sizes = <int, int>{};
  for (final c in comp) {
    sizes[c] = (sizes[c] ?? 0) + 1;
  }
  final mainComp = sizes.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  final keepNodes = [for (var i = 0; i < tLat.length; i++) if (comp[i] == mainComp) i];
  final sortedSizes = sizes.values.toList()..sort((a, b) => b.compareTo(a));
  log('연결 요소 ${sizes.length}개, 최대 ${sizes[mainComp]}노드 유지 (다음 큰 요소: ${sortedSizes.skip(1).take(5).join(', ')})');

  // 공간 순서(Morton)로 노드 재배열 → A* 메모리 지역성 향상
  keepNodes.sort((a, b) => _morton(tLat[a], tLng[a]).compareTo(_morton(tLat[b], tLng[b])));
  final remap = Int32List(tLat.length)..fillRange(0, tLat.length, -1);
  final gb = RoadGraphBuilder();
  for (final old in keepNodes) {
    remap[old] = gb.addNode(tLat[old] / 1e6, tLng[old] / 1e6);
  }
  for (var k = 0; k < eu.length; k++) {
    final u = remap[eu[k]], v = remap[ev[k]];
    if (u < 0 || v < 0) continue;
    gb.addEdge(u, v, flags: ef[k], name: en[k], feature: EdgeFeature.values[efe[k]]);
  }
  log('그래프: 노드 ${gb.nodeCount}, 도로 조각 ${gb.edgeCount}');

  // ── 3. 차도 위 보안등 거르기 ─────────────────────────────────
  // 고속도로·자동차전용도로에서 20m 안이고, 걸을 수 있는 길보다 그쪽에 더 가까운 보안등은
  // 보행자를 비추지 않으므로 통계·밝기 계산에서 뺀다(고가도로 아래 골목 보안등은 남는다).
  final walk = gb.build();
  var carDropped = 0, carDroppedW = 0;
  points.removeWhere((p) {
    if (p.type != FacilityType.light.index) return false;
    final lat = p.latE6 / 1e6, lng = p.lngE6 / 1e6;
    final dCar = carOnly.nearestM(lat, lng);
    if (dCar > 20) return false;
    final dWalk = walk.nearestEdge(lat, lng, maxM: 60).distanceM;
    if (dWalk <= dCar + 2) return false;
    carDropped++;
    carDroppedW += p.weight;
    return true;
  });
  log('고속도로·자동차전용도로 위 보안등 $carDropped지점(등 $carDroppedW개) 제외');

  // 같은 좌표·같은 종류는 하나로 합친다(가중치 합산, 최대 255).
  final merged = <String, _Fac>{};
  for (final p in points) {
    final key = '${p.type}:${p.latE6}:${p.lngE6}';
    final prev = merged[key];
    if (prev == null) {
      merged[key] = p;
    } else {
      prev.weight = (prev.weight + p.weight).clamp(1, 255);
    }
  }
  final facs = merged.values.toList()..sort((a, b) => _morton(a.latE6, a.lngE6).compareTo(_morton(b.latE6, b.lngE6)));
  final store = FacilityStore(
    Int32List.fromList([for (final f in facs) f.latE6]),
    Int32List.fromList([for (final f in facs) f.lngE6]),
    Uint8List.fromList([for (final f in facs) f.type]),
    Uint8List.fromList([for (final f in facs) f.weight]),
  );
  log('시설 합계 ${store.length}지점 (가로등·보안등 ${store.countOf(FacilityType.light)}, '
      'CCTV ${store.countOf(FacilityType.cctv)}, 비상벨 ${store.countOf(FacilityType.bell)})');

  log('엣지별 시설 밀집도 계산 중…');
  const model = SafetyModel();
  gb.computeLevels(store, model);
  final graph = gb.build();
  log('엣지 밀집도 계산 완료');

  // ── 4. 저장 ────────────────────────────────────────────────
  final facBytes = store.toBytes();
  final graphBytes = graph.toBytes();
  File('${out.path}/facilities.bin').writeAsBytesSync(facBytes);
  File('${out.path}/graph.bin').writeAsBytesSync(graphBytes);

  // '밝기 지도' 래스터(30m 격자): 앱이 지도 이동 중 계산 없이 바로 그리도록
  log('밝기 지도 래스터(30m) 계산 중…');
  final raster = SafetyRaster.build(graph, store, model: model, cellM: 30);
  final rasterBytes = raster.toBytes();
  File('${out.path}/heat.bin').writeAsBytesSync(rasterBytes);
  final roadCells = raster.values.where((v) => v != SafetyRaster.noRoad).length;
  log('래스터 ${raster.cols}×${raster.rows}, 도로 칸 $roadCells개, ${(rasterBytes.length / 1048576).toStringAsFixed(1)}MB');

  // 간단한 품질 지표: 엣지 안심점수 분포
  final scores = graph.computeEdgeScores(model);
  var dark = 0.0, totalLen = 0.0;
  for (var e = 0; e < graph.edgeCount; e++) {
    totalLen += graph.lengths[e];
    if (scores[e] < model.darkThreshold) dark += graph.lengths[e];
  }
  final meta = {
    'generatedAt': DateTime.now().toIso8601String(),
    'region': '부산광역시',
    'facilities': {
      'points': store.length,
      'lights': store.countOf(FacilityType.light),
      'cctvs': store.countOf(FacilityType.cctv),
      'bells': store.countOf(FacilityType.bell),
    },
    'filtered': {'carOnlyLights': carDropped, 'carOnlyLightUnits': carDroppedW},
    'graph': {
      'nodes': graph.nodeCount,
      'roadNames': graph.names.length - 1,
      'directedEdges': graph.edgeCount,
      'roadKm': (totalLen / 2 / 1000).round(),
      'darkRatio': double.parse((dark / totalLen).toStringAsFixed(3)),
      'osmTimestamp': osmTime,
    },
    'sources': [
      {'name': '전국보안등정보표준데이터(부산 16개 구·군)', 'provider': '공공데이터포털 data.go.kr', 'license': '이용허락범위 제한 없음'},
      {'name': '부산광역시_방범용 CCTV 정보_20251229', 'provider': '부산광역시 (data.go.kr)', 'license': '이용허락범위 제한 없음'},
      {'name': '전국안전비상벨위치표준데이터', 'provider': '공공데이터포털 data.go.kr', 'license': '이용허락범위 제한 없음'},
      {'name': 'OpenStreetMap 도로망·고속도로', 'provider': '© OpenStreetMap contributors', 'license': 'ODbL 1.0'},
    ],
  };
  File('${out.path}/meta.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(meta));
  log('저장: facilities.bin ${(facBytes.length / 1024).round()}KB, graph.bin ${(graphBytes.length / 1048576).toStringAsFixed(1)}MB, '
      '도로 ${meta['graph'] is Map ? (meta['graph'] as Map)['roadKm'] : '?'}km, 어두운 도로 비율 ${(dark / totalLen * 100).toStringAsFixed(1)}%');
}

class _Fac {
  final int type;
  final int latE6;
  final int lngE6;
  int weight;
  _Fac(this.type, double lat, double lng, this.weight)
      : latE6 = (lat * 1e6).round(),
        lngE6 = (lng * 1e6).round();
}

class _Stats {
  int rows = 0, kept = 0, dropped = 0, swapped = 0;
}

/// 부산 범위 안의 좌표로 정규화. 위·경도가 뒤바뀐 행은 바로잡는다.
({double lat, double lng})? _busanCoord(String? a, String? b, _Stats st) {
  final x = double.tryParse((a ?? '').trim()), y = double.tryParse((b ?? '').trim());
  if (x == null || y == null) return null;
  if (busanBounds.contains(x, y)) return (lat: x, lng: y);
  if (busanBounds.contains(y, x)) {
    st.swapped++;
    return (lat: y, lng: x);
  }
  return null;
}

_Stats _readLights(Directory dir, List<_Fac> out) {
  final st = _Stats();
  for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.csv'))) {
    final rows = _parseCsv(utf8.decode(f.readAsBytesSync(), allowMalformed: true));
    if (rows.isEmpty) continue;
    final h = rows.first.map((s) => s.trim()).toList();
    final iLat = h.indexOf('위도'), iLng = h.indexOf('경도'), iCnt = h.indexOf('설치개수');
    if (iLat < 0 || iLng < 0) {
      stderr.writeln('경고: ${f.path} 에 위도/경도 열이 없습니다');
      continue;
    }
    for (final r in rows.skip(1)) {
      if (r.length <= iLng) continue;
      st.rows++;
      final c = _busanCoord(r[iLat], r[iLng], st);
      if (c == null) {
        st.dropped++;
        continue;
      }
      final cnt = iCnt >= 0 && r.length > iCnt ? int.tryParse(r[iCnt].trim()) ?? 1 : 1;
      out.add(_Fac(FacilityType.light.index, c.lat, c.lng, cnt.clamp(1, 10)));
      st.kept++;
    }
  }
  return st;
}

_Stats _readCctv(Directory dir, List<_Fac> out) {
  final st = _Stats();
  for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.csv'))) {
    final bytes = f.readAsBytesSync();
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      // CP949 원본: 필요한 건 숫자(위·경도)뿐이라 바이트 보존 디코딩 후 열을 값으로 찾는다.
      text = latin1.decode(bytes);
    }
    final rows = _parseCsv(text);
    if (rows.isEmpty) continue;
    final h = rows.first.map((s) => s.trim()).toList();
    var iLat = h.indexOf('위도'), iLng = h.indexOf('경도');
    if (iLat < 0 || iLng < 0) {
      final guess = _inferLatLngColumns(rows);
      if (guess == null) {
        stderr.writeln('경고: ${f.path} 에서 위도/경도 열을 찾지 못했습니다');
        continue;
      }
      (iLat, iLng) = guess;
      stdout.writeln('  ${f.path}: 머리글을 읽을 수 없어 값 범위로 위도=$iLat열, 경도=$iLng열 추정');
    }
    for (final r in rows.skip(1)) {
      if (r.length <= iLng) continue;
      st.rows++;
      final c = _busanCoord(r[iLat], r[iLng], st);
      if (c == null) {
        st.dropped++;
        continue;
      }
      out.add(_Fac(FacilityType.cctv.index, c.lat, c.lng, 1));
      st.kept++;
    }
  }
  return st;
}

_Stats _readBells(Directory dir, List<_Fac> out) {
  final st = _Stats();
  for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
    final list = jsonDecode(f.readAsStringSync()) as List;
    for (final o in list.cast<Map<String, dynamic>>()) {
      st.rows++;
      final addr = '${o['RDNMADR'] ?? ''} ${o['LNMADR'] ?? ''} ${o['INSTITUTION_NM'] ?? ''}';
      if (!addr.contains('부산')) continue;
      final c = _busanCoord(o['LATITUDE']?.toString(), o['LONGITUDE']?.toString(), st);
      if (c == null) {
        st.dropped++;
        continue;
      }
      out.add(_Fac(FacilityType.bell.index, c.lat, c.lng, 1));
      st.kept++;
    }
  }
  return st;
}

/// 머리글이 깨진 CSV에서 값 범위로 위도·경도 열을 찾는다(앞 300행 기준).
(int, int)? _inferLatLngColumns(List<List<String>> rows) {
  final sample = rows.skip(1).take(300).toList();
  if (sample.isEmpty) return null;
  final cols = sample.map((r) => r.length).reduce((a, b) => a > b ? a : b);
  int best(bool Function(double v) inRange) {
    var bestCol = -1, bestHits = 0;
    for (var c = 0; c < cols; c++) {
      var hits = 0;
      for (final r in sample) {
        final v = c < r.length ? double.tryParse(r[c].trim()) : null;
        if (v != null && inRange(v)) hits++;
      }
      if (hits > bestHits) {
        bestHits = hits;
        bestCol = c;
      }
    }
    return bestHits >= sample.length * 0.8 ? bestCol : -1;
  }

  final lat = best((v) => v >= busanBounds.minLat && v <= busanBounds.maxLat);
  final lng = best((v) => v >= busanBounds.minLng && v <= busanBounds.maxLng);
  return lat >= 0 && lng >= 0 && lat != lng ? (lat, lng) : null;
}

/// RFC 4180 CSV 파서(따옴표 안의 쉼표·줄바꿈 처리, BOM 제거).
List<List<String>> _parseCsv(String text) {
  if (text.startsWith('﻿')) text = text.substring(1);
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == ',') {
      row.add(field.toString());
      field.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      if (row.length > 1 || row.first.isNotEmpty) rows.add(row);
      row = <String>[];
    } else {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

/// 무방향 그래프 연결 요소 번호.
Int32List _components(int n, List<int> eu, List<int> ev) {
  final deg = Int32List(n + 1);
  for (var k = 0; k < eu.length; k++) {
    deg[eu[k] + 1]++;
    deg[ev[k] + 1]++;
  }
  for (var i = 1; i <= n; i++) {
    deg[i] += deg[i - 1];
  }
  final fill = Int32List.fromList(deg);
  final adj = Int32List(eu.length * 2);
  for (var k = 0; k < eu.length; k++) {
    adj[fill[eu[k]]++] = ev[k];
    adj[fill[ev[k]]++] = eu[k];
  }
  final comp = Int32List(n)..fillRange(0, n, -1);
  final stack = <int>[];
  var c = 0;
  for (var s = 0; s < n; s++) {
    if (comp[s] >= 0) continue;
    comp[s] = c;
    stack.add(s);
    while (stack.isNotEmpty) {
      final u = stack.removeLast();
      for (var k = deg[u]; k < deg[u + 1]; k++) {
        final v = adj[k];
        if (comp[v] < 0) {
          comp[v] = c;
          stack.add(v);
        }
      }
    }
    c++;
  }
  return comp;
}

/// 좌표를 Z-order(Morton) 키로. 가까운 점이 메모리에서도 가깝게 놓인다.
int _morton(int latE6, int lngE6) {
  final x = ((lngE6 - 128000000) ~/ 50).clamp(0, 0xFFFFF);
  final y = ((latE6 - 34000000) ~/ 50).clamp(0, 0xFFFFF);
  var key = 0;
  for (var b = 19; b >= 0; b--) {
    key = (key << 2) | (((y >> b) & 1) << 1) | ((x >> b) & 1);
  }
  return key;
}

/// 길 안내 특징: 횡단보도·육교·지하도·계단
EdgeFeature _featureOf(String hw, Map<String, dynamic> tags, double wayLenM) {
  if (hw == 'steps') return EdgeFeature.steps;
  const ped = {'footway', 'path', 'pedestrian', 'corridor', 'cycleway'};
  final isPed = ped.contains(hw);
  final crossing = tags['crossing'] as String?;
  if (tags['footway'] == 'crossing' || tags['cycleway'] == 'crossing' || (isPed && crossing != null && crossing != 'no')) {
    return EdgeFeature.crossing;
  }
  if (isPed && tags['tunnel'] == 'yes') return EdgeFeature.underpass;
  // 강을 건너는 긴 보행교는 '육교'라고 부르지 않는다
  if (isPed && tags['bridge'] == 'yes' && wayLenM < 120) return EdgeFeature.overpass;
  return EdgeFeature.none;
}

/// 고속도로·자동차전용도로 선분 격자 색인(약 50m 칸)
class _CarOnlyIndex {
  static const _cell = 0.0005;
  final _cells = <int, List<int>>{};
  final _seg = <double>[];

  int get count => _seg.length ~/ 4;

  static int _key(int r, int c) => r * 1000000 + c;

  _CarOnlyIndex.fromOsm(File f) {
    if (!f.existsSync()) {
      stderr.writeln('경고: ${f.path} 가 없어 차도 위 보안등을 거르지 않습니다');
      return;
    }
    final osm = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final els = (osm['elements'] as List).cast<Map<String, dynamic>>();
    final la = <int, double>{}, lo = <int, double>{};
    for (final e in els) {
      if (e['type'] == 'node') {
        la[e['id'] as int] = (e['lat'] as num).toDouble();
        lo[e['id'] as int] = (e['lon'] as num).toDouble();
      }
    }
    for (final e in els) {
      if (e['type'] != 'way') continue;
      final refs = (e['nodes'] as List).cast<int>();
      for (var i = 1; i < refs.length; i++) {
        final a = refs[i - 1], b = refs[i];
        if (la.containsKey(a) && la.containsKey(b)) _add(la[a]!, lo[a]!, la[b]!, lo[b]!);
      }
    }
  }

  void _add(double aLat, double aLng, double bLat, double bLng) {
    final id = count;
    _seg.addAll([aLat, aLng, bLat, bLng]);
    final r0 = ((aLat < bLat ? aLat : bLat) / _cell).floor(), r1 = ((aLat > bLat ? aLat : bLat) / _cell).floor();
    final c0 = ((aLng < bLng ? aLng : bLng) / _cell).floor(), c1 = ((aLng > bLng ? aLng : bLng) / _cell).floor();
    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        _cells.putIfAbsent(_key(r, c), () => []).add(id);
      }
    }
  }

  /// 가장 가까운 자동차 전용 도로까지 거리(약 45m 안만 정확, 없으면 무한대)
  double nearestM(double lat, double lng) {
    final r = (lat / _cell).floor(), c = (lng / _cell).floor();
    var best = double.infinity;
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        for (final id in _cells[_key(r + dr, c + dc)] ?? const <int>[]) {
          final o = id * 4;
          final d = pointSegmentDistanceM(lat, lng, _seg[o], _seg[o + 1], _seg[o + 2], _seg[o + 3]);
          if (d < best) best = d;
        }
      }
    }
    return best;
  }
}
