import 'package:ansim_core/ansim_core.dart';
import 'package:geolocator/geolocator.dart';

enum LocationStatus { unknown, ok, serviceOff, denied, deniedForever }

/// GPS 현위치.
class LocationService {
  LocationStatus status = LocationStatus.unknown;

  Future<LocationStatus> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return status = LocationStatus.serviceOff;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    status = switch (p) {
      LocationPermission.always || LocationPermission.whileInUse => LocationStatus.ok,
      LocationPermission.deniedForever => LocationStatus.deniedForever,
      _ => LocationStatus.denied,
    };
    return status;
  }

  Future<GeoPoint?> current() async {
    if (status != LocationStatus.ok) return null;
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return GeoPoint(p.latitude, p.longitude);
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      return last == null ? null : GeoPoint(last.latitude, last.longitude);
    }
  }

  /// 걷는 중 위치 스트림(3m 이동마다).
  Stream<Position> watch({int distanceFilterM = 3}) => Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilterM,
          intervalDuration: const Duration(seconds: 2),
        ),
      );

  Future<void> openSettings() => Geolocator.openLocationSettings();
  Future<void> openAppSettings() => Geolocator.openAppSettings();
}
