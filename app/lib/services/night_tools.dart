import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:torch_light/torch_light.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 밤길 도구: 손전등, 화면 최대 밝기, 화면 꺼짐 방지.
class NightTools extends ChangeNotifier {
  bool torchAvailable = false;
  bool torchOn = false;
  bool brightOn = false;

  Future<void> init() async {
    try {
      torchAvailable = await TorchLight.isTorchAvailable();
    } catch (_) {
      torchAvailable = false;
    }
    notifyListeners();
  }

  /// 실패 시 사용자에게 보여줄 문구를 돌려준다.
  Future<String?> toggleTorch() async {
    try {
      if (torchOn) {
        await TorchLight.disableTorch();
        torchOn = false;
      } else {
        await TorchLight.enableTorch();
        torchOn = true;
      }
      notifyListeners();
      return null;
    } catch (_) {
      return '손전등을 켤 수 없어요(카메라 사용 중이거나 미지원 기기).';
    }
  }

  Future<void> toggleBrightness() async {
    try {
      if (brightOn) {
        await ScreenBrightness.instance.resetApplicationScreenBrightness();
      } else {
        await ScreenBrightness.instance.setApplicationScreenBrightness(1.0);
      }
      brightOn = !brightOn;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> keepAwake(bool on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (_) {}
  }

  Future<void> releaseAll() async {
    if (torchOn) {
      try {
        await TorchLight.disableTorch();
      } catch (_) {}
      torchOn = false;
    }
    if (brightOn) {
      try {
        await ScreenBrightness.instance.resetApplicationScreenBrightness();
      } catch (_) {}
      brightOn = false;
    }
    await keepAwake(false);
  }
}

/// 음성 안내(한국어·영어·일본어). [locale]이 바뀌면 다음 말할 때 TTS 언어를 바꾼다.
class Voice {
  final _tts = FlutterTts();
  bool enabled = true;
  String _locale = 'ko-KR';
  String? _applied;

  /// TTS 언어 코드: 'ko-KR' | 'en-US' | 'ja-JP'
  set locale(String v) => _locale = v;

  Future<void> _init() async {
    if (_applied == _locale) return;
    try {
      await _tts.setLanguage(_locale);
      await _tts.setSpeechRate(0.5);
    } catch (_) {}
    _applied = _locale;
  }

  Future<void> say(String text) async {
    if (!enabled) return;
    await _init();
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
