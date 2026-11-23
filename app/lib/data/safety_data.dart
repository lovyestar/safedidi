import 'dart:convert';

import 'package:ansim_core/ansim_core.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 앱에 내장된 부산 안전시설·보행 도로망·밝기 래스터. 서버 없이 기기 안에서만 계산한다.
class SafetyData {
  final RoadGraph graph;
  final FacilityStore facilities;
  final SafetyRaster raster;
  final SafeRoutePlanner planner;
  final Map<String, dynamic> meta;

  SafetyData._(this.graph, this.facilities, this.raster, this.planner, this.meta);

  static Future<SafetyData> load() async {
    final graphBytes = await rootBundle.load('assets/data/graph.bin');
    final facBytes = await rootBundle.load('assets/data/facilities.bin');
    final heatBytes = await rootBundle.load('assets/data/heat.bin');
    final meta = jsonDecode(await rootBundle.loadString('assets/data/meta.json')) as Map<String, dynamic>;
    final graph = RoadGraph.fromBytes(graphBytes);
    final facilities = FacilityStore.fromBytes(facBytes);
    final raster = SafetyRaster.fromBytes(heatBytes);
    final planner = SafeRoutePlanner(graph, facilities);
    // 공간 인덱스·엣지 점수를 미리 만들어 첫 길찾기를 빠르게
    graph.nodeIndex;
    facilities.index;
    planner.router.edgeScores;
    return SafetyData._(graph, facilities, raster, planner, meta);
  }

  String get osmTimestamp => (meta['graph'] as Map?)?['osmTimestamp'] as String? ?? '';
}
