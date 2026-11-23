import 'dart:math' as math;
import 'dart:typed_data';

import 'geo.dart';
import 'road_graph.dart';
import 'safety_model.dart';

/// 그래프 위의 경로(노드·엣지 순서).
class RoutePath {
  final List<int> nodes;
  final List<int> edges;
  final double lengthM;
  final double cost;
  const RoutePath(this.nodes, this.edges, this.lengthM, this.cost);

  List<GeoPoint> points(RoadGraph g) => [for (final n in nodes) g.point(n)];
}

/// 안전 가중치 A* 길찾기.
///
/// 엣지 비용 = 길이 × costFactor(안심점수, 도로등급, alpha)
///   alpha = 0 → 순수 최단거리, alpha가 클수록 어두운 길을 피한다.
/// 휴리스틱 = 직선거리(비용 ≥ 길이이므로 admissible).
/// 탐색 버퍼를 재사용하므로 한 인스턴스를 동시에 여러 곳에서 쓰면 안 된다.
class AStarRouter {
  final RoadGraph graph;
  final SafetyModel model;
  late final Float32List edgeScores = graph.computeEdgeScores(model);

  final Float64List _g;
  final Int32List _cameEdge;
  final Int32List _cameNode;
  final Uint32List _seen;
  final Uint32List _closed;
  int _stamp = 0;

  /// 마지막 탐색에서 확정한 노드 수(성능 확인용).
  int lastExpanded = 0;

  AStarRouter(this.graph, {this.model = const SafetyModel()})
      : _g = Float64List(graph.nodeCount),
        _cameEdge = Int32List(graph.nodeCount),
        _cameNode = Int32List(graph.nodeCount),
        _seen = Uint32List(graph.nodeCount),
        _closed = Uint32List(graph.nodeCount);

  RoutePath? route(int src, int dst, {double alpha = 0, double? marginM}) {
    if (src < 0 || dst < 0) return null;
    if (src == dst) return RoutePath([src], const [], 0, 0);
    if (++_stamp == 0xFFFFFFFF) {
      _seen.fillRange(0, _seen.length, 0);
      _closed.fillRange(0, _closed.length, 0);
      _stamp = 1;
    }
    final stamp = _stamp;
    final g = graph;
    final dLat = g.lat(dst), dLng = g.lng(dst);
    final mLng = metersPerDegLng(dLat);
    final direct = haversineM(g.lat(src), g.lng(src), dLat, dLng);
    final margin = marginM ?? math.max(800.0, direct * 0.6);
    final box = GeoBounds.fromPoints([g.point(src), g.point(dst)]).expandedBy(margin);
    final minLat = (box.minLat * 1e6).floor(), maxLat = (box.maxLat * 1e6).ceil();
    final minLng = (box.minLng * 1e6).floor(), maxLng = (box.maxLng * 1e6).ceil();

    double h(int v) {
      final dy = (g.lat(v) - dLat) * metersPerDegLat;
      final dx = (g.lng(v) - dLng) * mLng;
      return math.sqrt(dx * dx + dy * dy) * 0.999;
    }

    final heap = _MinHeap();
    _g[src] = 0;
    _seen[src] = stamp;
    _cameEdge[src] = -1;
    _cameNode[src] = -1;
    heap.push(h(src), src);
    var expanded = 0;
    var found = false;
    final offsets = g.offsets, targets = g.targets, lengths = g.lengths, flags = g.edgeFlags;
    final latE6 = g.latE6, lngE6 = g.lngE6;
    final scores = edgeScores;

    while (heap.isNotEmpty) {
      final u = heap.pop();
      if (_closed[u] == stamp) continue;
      _closed[u] = stamp;
      expanded++;
      if (u == dst) {
        found = true;
        break;
      }
      final gu = _g[u];
      for (var e = offsets[u]; e < offsets[u + 1]; e++) {
        final v = targets[e];
        if (_closed[v] == stamp) continue;
        final la = latE6[v], lo = lngE6[v];
        if (la < minLat || la > maxLat || lo < minLng || lo > maxLng) continue;
        final c = alpha <= 0
            ? lengths[e].toDouble()
            : lengths[e] * model.costFactor(scores[e], flags[e], alpha);
        final ng = gu + c;
        if (_seen[v] != stamp || ng < _g[v]) {
          _seen[v] = stamp;
          _g[v] = ng;
          _cameEdge[v] = e;
          _cameNode[v] = u;
          heap.push(ng + h(v), v);
        }
      }
    }
    lastExpanded = expanded;
    if (!found) return null;

    final nodes = <int>[];
    final edges = <int>[];
    var length = 0.0;
    for (var v = dst; v != -1; v = _cameNode[v]) {
      nodes.add(v);
      final e = _cameEdge[v];
      if (e >= 0) {
        edges.add(e);
        length += lengths[e];
      }
    }
    return RoutePath(nodes.reversed.toList(), edges.reversed.toList(), length, _g[dst]);
  }
}

/// (키, 노드) 이진 최소 힙.
class _MinHeap {
  Float64List _keys = Float64List(1024);
  Int32List _vals = Int32List(1024);
  int _size = 0;

  bool get isNotEmpty => _size > 0;

  void push(double key, int val) {
    if (_size == _keys.length) {
      _keys = Float64List(_size * 2)..setAll(0, _keys);
      _vals = Int32List(_size * 2)..setAll(0, _vals);
    }
    var i = _size++;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_keys[p] <= key) break;
      _keys[i] = _keys[p];
      _vals[i] = _vals[p];
      i = p;
    }
    _keys[i] = key;
    _vals[i] = val;
  }

  int pop() {
    final top = _vals[0];
    final lastKey = _keys[--_size];
    final lastVal = _vals[_size];
    var i = 0;
    while (true) {
      var c = 2 * i + 1;
      if (c >= _size) break;
      if (c + 1 < _size && _keys[c + 1] < _keys[c]) c++;
      if (_keys[c] >= lastKey) break;
      _keys[i] = _keys[c];
      _vals[i] = _vals[c];
      i = c;
    }
    _keys[i] = lastKey;
    _vals[i] = lastVal;
    return top;
  }
}
