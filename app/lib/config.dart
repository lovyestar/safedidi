import 'package:ansim_core/ansim_core.dart';

/// 빌드 시 주입하는 API 키.
///   flutter run --dart-define-from-file=keys.json
/// keys.json 은 Git에 올리지 않는다(keys.example.json 참고).
/// 지도는 OpenStreetMap 타일이라 키가 필요 없다.
class AppConfig {
  /// 카카오 REST API 키(로컬 장소 검색)
  static const kakaoRestKey = String.fromEnvironment('KAKAO_REST_API_KEY');

  /// SK open API TMAP appKey(보행자 경로). 없으면 앱 내장 최단경로로 대체.
  static const tmapAppKey = String.fromEnvironment('TMAP_APP_KEY');

  static bool get hasKakao => kakaoRestKey.isNotEmpty;
  static bool get hasTmap => tmapAppKey.isNotEmpty;

  /// 위치를 모를 때의 기본 지도 중심(부산 서면).
  static const defaultCenter = GeoPoint(35.1577, 129.0594);
}
