import 'dart:math' as math;
import 'dart:typed_data';

import 'geo.dart';

/// 고정 크기 격자 버킷 공간 인덱스.
/// 점 i의 좌표는 [latOf]/[lngOf] 콜백으로 읽는다(원본 배열 형식에 독립적).
class GridIndex {
  final double minLat, minLng, cellLat, cellLng;
  final int rows, cols;
  final Int32List _cellStart; // rows*cols + 1
  final Int32List _items;

  GridIndex._(this.minLat, this.minLng, this.cellLat, this.cellLng, this.rows, this.cols,
      this._cellStart, this._items);

  factory GridIndex.build({
    required int count,
    required double Function(int i) latOf,
    required double Function(int i) lngOf,
    required double cellSizeM,
    GeoBounds? bounds,
  }) {
    var b = bounds;
    if (b == null) {
      var minLat = 90.0, minLng = 180.0, maxLat = -90.0, maxLng = -180.0;
      for (var i = 0; i < count; i++) {
        final la = latOf(i), lo = lngOf(i);
        if (la < minLat) minLat = la;
        if (la > maxLat) maxLat = la;
        if (lo < minLng) minLng = lo;
        if (lo > maxLng) maxLng = lo;
      }
      if (count == 0) {
        minLat = minLng = 0;
        maxLat = maxLng = 0.001;
      }
      b = GeoBounds(minLat, minLng, maxLat, maxLng);
    }
    final cellLat = cellSizeM / metersPerDegLat;
    final cellLng = cellSizeM / metersPerDegLng((b.minLat + b.maxLat) / 2);
    final rows = math.max(1, ((b.maxLat - b.minLat) / cellLat).floor() + 1);
    final cols = math.max(1, ((b.maxLng - b.minLng) / cellLng).floor() + 1);
    final cellOf = Int32List(count);
    final counts = Int32List(rows * cols + 1);
    for (var i = 0; i < count; i++) {
      var r = ((latOf(i) - b.minLat) / cellLat).floor();
      var c = ((lngOf(i) - b.minLng) / cellLng).floor();
      if (r < 0) r = 0;
      if (r >= rows) r = rows - 1;
      if (c < 0) c = 0;
      if (c >= cols) c = cols - 1;
      final cell = r * cols + c;
      cellOf[i] = cell;
      counts[cell + 1]++;
    }
    for (var k = 1; k < counts.length; k++) {
      counts[k] += counts[k - 1];
    }
    final fill = Int32List.fromList(counts);
    final items = Int32List(count);
    for (var i = 0; i < count; i++) {
      items[fill[cellOf[i]]++] = i;
    }
    return GridIndex._(b.minLat, b.minLng, cellLat, cellLng, rows, cols, counts, items);
  }

  int _row(double lat) {
    final r = ((lat - minLat) / cellLat).floor();
    return r < 0 ? 0 : (r >= rows ? rows - 1 : r);
  }

  int _col(double lng) {
    final c = ((lng - minLng) / cellLng).floor();
    return c < 0 ? 0 : (c >= cols ? cols - 1 : c);
  }

  /// (lat,lng) 반경 [radiusM] 안에 있을 수 있는 후보 점들을 방문한다.
  /// 정확한 거리 필터링은 호출자가 한다.
  void forEachCandidate(double lat, double lng, double radiusM, void Function(int i) visit) {
    final dLat = radiusM / metersPerDegLat;
    final dLng = radiusM / metersPerDegLng(lat);
    forEachInBox(lat - dLat, lng - dLng, lat + dLat, lng + dLng, visit);
  }

  void forEachInBox(double aLat, double aLng, double bLat, double bLng, void Function(int i) visit) {
    if (bLat < minLat - cellLat || aLat > minLat + rows * cellLat) return;
    if (bLng < minLng - cellLng || aLng > minLng + cols * cellLng) return;
    final r0 = _row(aLat), r1 = _row(bLat);
    final c0 = _col(aLng), c1 = _col(bLng);
    for (var r = r0; r <= r1; r++) {
      final base = r * cols;
      for (var c = c0; c <= c1; c++) {
        final cell = base + c;
        final end = _cellStart[cell + 1];
        for (var k = _cellStart[cell]; k < end; k++) {
          visit(_items[k]);
        }
      }
    }
  }
}
