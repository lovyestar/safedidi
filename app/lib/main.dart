import 'package:flutter/material.dart';

import 'controllers/theme_controller.dart';
import 'data/safety_data.dart';
import 'services/prefs.dart';
import 'theme.dart';
import 'ui/kit.dart';
import 'ui/logo.dart';
import 'ui/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AnsimDidiApp());
}

class AnsimDidiApp extends StatefulWidget {
  const AnsimDidiApp({super.key});

  @override
  State<AnsimDidiApp> createState() => _AnsimDidiAppState();
}

class _AnsimDidiAppState extends State<AnsimDidiApp> {
  final theme = ThemeController();
  final prefs = AppPrefs();
  late final Future<SafetyData> _data = _boot();

  Future<SafetyData> _boot() async {
    await prefs.load();
    // 저장된 테마를 먼저 적용하고, 바꿀 때마다 저장
    theme
      ..restore(ThemeChoice.values.firstWhere((c) => c.name == prefs.theme, orElse: () => ThemeChoice.auto))
      ..onChanged = (c) => prefs.setTheme(c.name);
    return SafetyData.load();
  }

  @override
  void dispose() {
    theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: theme,
      builder: (context, _) => MaterialApp(
        title: '안심디디',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: theme.mode,
        home: FutureBuilder<SafetyData>(
          future: _data,
          builder: (context, snap) {
            if (snap.hasData) return HomePage(data: snap.data!, theme: theme, prefs: prefs);
            return _Splash(error: snap.error);
          },
        ),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  final Object? error;
  const _Splash({this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const AppLogo(size: 104),
          const SizedBox(height: 18),
          const Text('안심디디', style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
          const SizedBox(height: 4),
          const Text('밝은 길로 안심 귀가', style: TextStyle(color: AppColors.lamp, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 22),
          if (error == null)
            const LampSpinner(size: 26)
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text('데이터를 불러오지 못했어요\n$error',
                  textAlign: TextAlign.center, style: const TextStyle(color: AppColors.plain, height: 1.5)),
            ),
        ]),
      ),
    );
  }
}
