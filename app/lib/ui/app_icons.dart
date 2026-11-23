import 'package:flutter/widgets.dart';

/// 안심디디 아이콘(Phosphor Icons, MIT — assets/fonts/LICENSE-Phosphor.txt). 기본 머티리얼 아이콘 대신 한곳에서 고른다.
/// phosphor_flutter 패키지는 최신 Flutter에서 컴파일되지 않아(IconData가 final) 글꼴만 넣고 코드포인트를 직접 쓴다.
/// 굵은 선(Bold)은 기본 UI, 채움(Fill)은 색이 들어가는 배지·강조에 쓴다.
abstract final class Ic {
  // 기본 동작
  static const IconData menu = IconData(0xe2f0, fontFamily: 'PhosphorBold');
  static const IconData search = IconData(0xe30c, fontFamily: 'PhosphorBold');
  static const IconData back = IconData(0xe058, fontFamily: 'PhosphorBold');
  static const IconData close = IconData(0xe4f6, fontFamily: 'PhosphorBold');
  static const IconData clear = IconData(0xe4f8, fontFamily: 'PhosphorFill');
  static const IconData more = IconData(0xe1fe, fontFamily: 'PhosphorBold');
  static const IconData chevron = IconData(0xe13a, fontFamily: 'PhosphorBold');
  static const IconData plus = IconData(0xe3d4, fontFamily: 'PhosphorBold');
  static const IconData check = IconData(0xe182, fontFamily: 'PhosphorBold');
  static const IconData swap = IconData(0xe098, fontFamily: 'PhosphorBold');
  static const IconData trash = IconData(0xe4a6, fontFamily: 'PhosphorBold');
  static const IconData copy = IconData(0xe1ca, fontFamily: 'PhosphorBold');
  static const IconData list = IconData(0xe2f2, fontFamily: 'PhosphorBold');
  static const IconData refresh = IconData(0xe094, fontFamily: 'PhosphorBold');

  // 장소
  static const IconData home = IconData(0xe2c2, fontFamily: 'PhosphorFill');
  static const IconData work = IconData(0xe102, fontFamily: 'PhosphorFill');
  static const IconData recent = IconData(0xe1a0, fontFamily: 'PhosphorBold');
  static const IconData place = IconData(0xe316, fontFamily: 'PhosphorFill');
  static const IconData placeAdd = IconData(0xe314, fontFamily: 'PhosphorFill');
  static const IconData store = IconData(0xe470, fontFamily: 'PhosphorFill');
  static const IconData police = IconData(0xec34, fontFamily: 'PhosphorFill');
  static const IconData pharmacy = IconData(0xe700, fontFamily: 'PhosphorFill');
  static const IconData emergency = IconData(0xe56e, fontFamily: 'PhosphorFill');
  static const IconData subway = IconData(0xe4a0, fontFamily: 'PhosphorFill');
  static const IconData school = IconData(0xe62c, fontFamily: 'PhosphorFill');
  static const IconData cafe = IconData(0xe1c2, fontFamily: 'PhosphorFill');
  static const IconData food = IconData(0xe262, fontFamily: 'PhosphorFill');
  static const IconData hospital = IconData(0xe844, fontFamily: 'PhosphorFill');
  static const IconData publicOffice = IconData(0xe0b4, fontFamily: 'PhosphorFill');
  static const IconData hotel = IconData(0xe0cc, fontFamily: 'PhosphorFill');
  static const IconData parking = IconData(0xec08, fontFamily: 'PhosphorFill');
  static const IconData shopping = IconData(0xe416, fontFamily: 'PhosphorFill');
  static const IconData park = IconData(0xe6da, fontFamily: 'PhosphorFill');

  // 안전시설
  static const IconData light = IconData(0xe2dc, fontFamily: 'PhosphorFill');
  static const IconData cctv = IconData(0xeca4, fontFamily: 'PhosphorFill');
  static const IconData bell = IconData(0xe5e8, fontFamily: 'PhosphorFill');
  static const IconData sos = IconData(0xe9b8, fontFamily: 'PhosphorFill');
  static const IconData shield = IconData(0xe40c, fontFamily: 'PhosphorFill');

  // 지도·안내
  static const IconData navigate = IconData(0xeade, fontFamily: 'PhosphorFill');
  static const IconData myLocation = IconData(0xe1d8, fontFamily: 'PhosphorBold');
  static const IconData compass = IconData(0xe1c8, fontFamily: 'PhosphorFill');
  static const IconData layers = IconData(0xe468, fontFamily: 'PhosphorBold');
  static const IconData walk = IconData(0xe73a, fontFamily: 'PhosphorFill');
  static const IconData footprints = IconData(0xea88, fontFamily: 'PhosphorFill');
  static const IconData flag = IconData(0xea38, fontFamily: 'PhosphorFill');
  static const IconData stairs = IconData(0xe8ec, fontFamily: 'PhosphorBold');
  static const IconData path = IconData(0xe39c, fontFamily: 'PhosphorBold');

  // 밤길 도구
  static const IconData torchOn = IconData(0xe246, fontFamily: 'PhosphorFill');
  static const IconData torchOff = IconData(0xe246, fontFamily: 'PhosphorBold');
  static const IconData bright = IconData(0xe472, fontFamily: 'PhosphorFill');
  static const IconData sun = IconData(0xe472, fontFamily: 'PhosphorFill');
  static const IconData moon = IconData(0xe58e, fontFamily: 'PhosphorFill');
  static const IconData auto = IconData(0xe19a, fontFamily: 'PhosphorFill');
  static const IconData stop = IconData(0xe46e, fontFamily: 'PhosphorFill');

  // 안전 기능·정보
  static const IconData phone = IconData(0xe3b8, fontFamily: 'PhosphorFill');
  static const IconData sms = IconData(0xe17a, fontFamily: 'PhosphorFill');
  static const IconData guardian = IconData(0xe4d6, fontFamily: 'PhosphorFill');
  static const IconData timer = IconData(0xe492, fontFamily: 'PhosphorFill');
  static const IconData vibrate = IconData(0xe4d8, fontFamily: 'PhosphorFill');
  static const IconData info = IconData(0xe2ce, fontFamily: 'PhosphorFill');
  static const IconData warning = IconData(0xe4e2, fontFamily: 'PhosphorFill');
  static const IconData ok = IconData(0xe184, fontFamily: 'PhosphorFill');
  static const IconData data = IconData(0xe150, fontFamily: 'PhosphorFill');
  static const IconData key = IconData(0xe2d6, fontFamily: 'PhosphorFill');
  static const IconData noResult = IconData(0xe30e, fontFamily: 'PhosphorBold');
  static const IconData explore = IconData(0xe31a, fontFamily: 'PhosphorFill');
}
