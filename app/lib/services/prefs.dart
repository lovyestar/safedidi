import 'dart:convert';

import 'package:ansim_core/ansim_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kakao_local.dart';

/// 기기에 저장하는 사용자 설정: 집·회사, 최근 검색, 보호자 연락처, 안전 기능 on/off.
class AppPrefs extends ChangeNotifier {
  late final SharedPreferences _p;

  PlaceRef? home;
  PlaceRef? work;
  List<PlaceRef> recent = [];
  String guardianPhone = '';
  bool shakeSos = true;
  bool safetyTimer = true;
  int timerBufferMin = 5;

  /// 화면 테마: 'auto' | 'dark' | 'light'
  String theme = 'auto';

  /// 길 안내 언어(음성·안내 화면): 'ko' | 'en' | 'ja'
  String guideLang = 'ko';

  static const _maxRecent = 12;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    home = _decode(_p.getString('home'));
    work = _decode(_p.getString('work'));
    recent = (_p.getStringList('recent') ?? const []).map(_decode).whereType<PlaceRef>().toList();
    guardianPhone = _p.getString('guardianPhone') ?? '';
    shakeSos = _p.getBool('shakeSos') ?? true;
    safetyTimer = _p.getBool('safetyTimer') ?? true;
    timerBufferMin = _p.getInt('timerBufferMin') ?? 5;
    theme = _p.getString('theme') ?? 'auto';
    guideLang = _p.getString('guideLang') ?? 'ko';
  }

  Future<void> setGuideLang(String v) async {
    guideLang = v;
    await _p.setString('guideLang', v);
    notifyListeners();
  }

  Future<void> setTheme(String v) async {
    theme = v;
    await _p.setString('theme', v);
  }

  Future<void> setHome(PlaceRef? p) async {
    home = p;
    p == null ? await _p.remove('home') : await _p.setString('home', _encode(p));
    notifyListeners();
  }

  Future<void> setWork(PlaceRef? p) async {
    work = p;
    p == null ? await _p.remove('work') : await _p.setString('work', _encode(p));
    notifyListeners();
  }

  Future<void> addRecent(PlaceRef p) async {
    if (p.isCurrentLocation) return;
    recent.removeWhere((r) => r.name == p.name && distanceM(r.point, p.point) < 30);
    recent.insert(0, p);
    if (recent.length > _maxRecent) recent = recent.sublist(0, _maxRecent);
    await _p.setStringList('recent', recent.map(_encode).toList());
    notifyListeners();
  }

  Future<void> removeRecent(PlaceRef p) async {
    recent.remove(p);
    await _p.setStringList('recent', recent.map(_encode).toList());
    notifyListeners();
  }

  Future<void> clearRecent() async {
    recent = [];
    await _p.remove('recent');
    notifyListeners();
  }

  Future<void> setGuardianPhone(String v) async {
    guardianPhone = v.replaceAll(RegExp(r'[^0-9+]'), '');
    await _p.setString('guardianPhone', guardianPhone);
    notifyListeners();
  }

  Future<void> setShakeSos(bool v) async {
    shakeSos = v;
    await _p.setBool('shakeSos', v);
    notifyListeners();
  }

  Future<void> setSafetyTimer(bool v) async {
    safetyTimer = v;
    await _p.setBool('safetyTimer', v);
    notifyListeners();
  }

  static String _encode(PlaceRef p) => jsonEncode({
        'name': p.name,
        'address': p.address,
        'category': p.category,
        'lat': p.point.lat,
        'lng': p.point.lng,
      });

  static PlaceRef? _decode(String? s) {
    if (s == null) return null;
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return PlaceRef(
        name: m['name'] as String,
        address: m['address'] as String?,
        category: m['category'] as String?,
        point: GeoPoint((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()),
      );
    } catch (_) {
      return null;
    }
  }
}
