// 안내 시연: 앱(디버그 빌드)이 logcat에 남긴 안심 경로를 따라 에뮬레이터 GPS를 움직인다.
//
// 사용:
//   cd tools/preprocess
//   dart run bin/walk_demo.dart [--speed 5] [--detour] [--serial emulator-5554]
// 그다음 앱에서 도착지를 고르고 [안심 경로로 안내 시작]을 누르면 걷기 시작한다.
//   --speed  초당 이동 거리(m). 실제 걸음은 약 1.2m/s, 시연은 5m/s 권장
//   --detour 경로의 35% 지점에서 옆길로 70m 벗어나 앱의 재탐색을 보여준다

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:ansim_core/ansim_core.dart';

late String _adb;
late String _serial;

// logcat에서 모은 경로 조각: id → (조각번호 → 점들)
final _chunks = <String, Map<int, List<GeoPoint>>>{};
final _totals = <String, int>{};
List<GeoPoint>? _latest;
String? _latestId;
bool _navStarted = false;
bool _navEnded = false;

Future<void> main(List<String> args) async {
  String opt(String name, String def) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : def;
  }

  final sdk = Platform.environment['ANDROID_HOME'] ??
      '${Platform.environment['LOCALAPPDATA']}\\Android\\Sdk';
  _adb = opt('--adb', '$sdk\\platform-tools\\adb.exe');
  _serial = opt('--serial', 'emulator-5554');
  final speed = double.parse(opt('--speed', '5'));
  final detour = args.contains('--detour');

  // adb 연결이 잠깐 끊겨도 로그를 계속 받도록, logcat이 끝나면 다시 붙는다(최근 줄 재생은 중복돼도 무해).
  var running = true;
  Process? current;
  Future<void> follow({bool first = true}) async {
    while (running) {
      final p = await Process.start(_adb, ['-s', _serial, 'logcat', '-T', first ? '1' : '40', '-v', 'brief', 'flutter:I', '*:S']);
      current = p;
      first = false;
      p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(_onLogLine);
      await p.exitCode;
      if (running) {
        _say('(logcat 연결이 끊겨 다시 연결합니다)');
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  unawaited(follow());
  final logcat = _Stopper(() {
    running = false;
    current?.kill();
  });

  _say('앱에서 도착지를 고르고 [안심 경로로 안내 시작]을 눌러 주세요. (대기 중)');
  await _waitUntil(() => _navStarted && _latest != null, const Duration(minutes: 10));
  if (!_navStarted) {
    _say('10분 동안 안내가 시작되지 않아 종료합니다.');
    logcat.kill();
    return;
  }

  var route = _latest!;
  var routeId = _latestId;
  var along = 0.0;
  var detoured = false;
  _say('안내 시작 감지: 경로 ${polylineLengthM(route).round()}m, 초당 ${speed}m로 걷습니다.');

  while (!_navEnded) {
    // 앱이 스스로 경로를 바꿨으면(재탐색) 새 경로의 현재 위치부터 이어서 걷는다.
    if (_latestId != routeId && _latest != null) {
      final here = _pointAt(route, along);
      route = _latest!;
      routeId = _latestId;
      along = progressOnPolyline(route, here).alongM;
      _say('새 안심 경로로 갈아탐: 남은 ${(polylineLengthM(route) - along).round()}m');
    }
    final total = polylineLengthM(route);
    if (detour && !detoured && along > total * 0.35) {
      detoured = true;
      await _detour(route, along);
      continue;
    }
    if (along >= total) {
      await _fix(route.last);
      _say('목적지 도착 지점에 왔습니다.');
      break;
    }
    await _fix(_pointAt(route, along));
    await Future<void>.delayed(const Duration(seconds: 1));
    along += speed;
  }
  await _waitUntil(() => _navEnded, const Duration(seconds: 8));
  _say(_navEnded ? '앱이 안내를 마쳤습니다.' : '시연 스크립트를 끝냅니다.');
  logcat.kill();
}

class _Stopper {
  final void Function() kill;
  _Stopper(this.kill);
}

/// 진행 방향 오른쪽으로 70m 벗어났다가, 앱이 재탐색하면 새 경로로 돌아간다.
Future<void> _detour(List<GeoPoint> route, double along) async {
  final p = _pointAt(route, along);
  final q = _pointAt(route, along + 10);
  final mLng = metersPerDegLng(p.lat);
  final dx = (q.lng - p.lng) * mLng, dy = (q.lat - p.lat) * metersPerDegLat;
  final len = math.sqrt(dx * dx + dy * dy);
  final ux = len == 0 ? 1.0 : dy / len, uy = len == 0 ? 0.0 : -dx / len; // 오른쪽 수직
  _say('일부러 경로를 벗어납니다(옆길로 70m)…');
  final before = _latestId;
  for (final off in [20.0, 40.0, 55.0, 70.0, 70.0]) {
    await _fix(GeoPoint(p.lat + uy * off / metersPerDegLat, p.lng + ux * off / mLng));
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  _say('앱의 재탐색을 기다리는 중…');
  await _waitUntil(() => _latestId != before, const Duration(seconds: 25));
  _say(_latestId != before ? '앱이 현위치에서 안심 경로를 다시 찾았습니다.' : '재탐색이 감지되지 않아 원래 경로로 돌아갑니다.');
}

void _onLogLine(String line) {
  final i = line.indexOf('ANSIM_');
  if (i < 0) return;
  final msg = line.substring(i).trim();
  if (msg.startsWith('ANSIM_NAV start')) {
    _navStarted = true;
    _navEnded = false;
  } else if (msg.startsWith('ANSIM_NAV')) {
    if (_navStarted) _navEnded = true;
  } else if (msg.startsWith('ANSIM_ROUTE ')) {
    final parts = msg.split(' ');
    if (parts.length < 4) return;
    final id = parts[1];
    final nm = parts[2].split('/');
    final idx = int.parse(nm[0]), total = int.parse(nm[1]);
    final pts = [
      for (final s in parts[3].split(';'))
        if (s.contains(','))
          GeoPoint(double.parse(s.split(',')[0]), double.parse(s.split(',')[1])),
    ];
    (_chunks[id] ??= {})[idx] = pts;
    _totals[id] = total;
    if (_chunks[id]!.length == total) {
      _latest = [for (var k = 1; k <= total; k++) ..._chunks[id]![k]!];
      _latestId = id;
    }
  }
}

GeoPoint _pointAt(List<GeoPoint> pts, double along) {
  var acc = 0.0;
  for (var i = 1; i < pts.length; i++) {
    final seg = distanceM(pts[i - 1], pts[i]);
    if (acc + seg >= along) {
      final t = seg == 0 ? 0.0 : (along - acc) / seg;
      final a = pts[i - 1], b = pts[i];
      return GeoPoint(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t);
    }
    acc += seg;
  }
  return pts.last;
}

Future<void> _fix(GeoPoint p) async {
  // 주의: geo fix 인자 순서는 경도, 위도
  await Process.run(_adb, ['-s', _serial, 'emu', 'geo', 'fix', p.lng.toStringAsFixed(6), p.lat.toStringAsFixed(6)]);
}

Future<void> _waitUntil(bool Function() cond, Duration timeout) async {
  final end = DateTime.now().add(timeout);
  while (!cond() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
}

void _say(String s) {
  final t = DateTime.now();
  stdout.writeln('[${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}] $s');
}
