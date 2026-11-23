import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

/// 폰을 세게 3번 흔들면(1.2초 안) 콜백. 오작동을 줄이려고 5초 쿨다운.
class ShakeDetector {
  final void Function() onShake;
  final double threshold; // 중력 제외 가속도(m/s²)
  StreamSubscription<UserAccelerometerEvent>? _sub;
  final _hits = <DateTime>[];
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  ShakeDetector({required this.onShake, this.threshold = 17});

  bool get running => _sub != null;

  void start() {
    _sub ??= userAccelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen((e) {
      final g = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      if (g < threshold) return;
      final now = DateTime.now();
      if (_hits.isNotEmpty && now.difference(_hits.last).inMilliseconds < 180) return; // 같은 흔들림
      _hits.add(now);
      _hits.removeWhere((t) => now.difference(t).inMilliseconds > 1200);
      if (_hits.length >= 3 && now.difference(_last).inSeconds >= 5) {
        _last = now;
        _hits.clear();
        onShake();
      }
    }, onError: (_) {});
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _hits.clear();
  }
}
