import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'app_icons.dart';
import 'kit.dart';
import 'widgets.dart';

enum SafetyCheckResult { ok, help, noResponse }

/// 안심 타이머: "괜찮으세요?" 60초 안에 응답이 없으면 noResponse.
Future<SafetyCheckResult> showSafetyCheck(BuildContext context, {int seconds = 60}) async {
  final r = await showAppDialog<SafetyCheckResult>(
    context,
    dismissible: false,
    builder: (_) => _SafetyCheckDialog(seconds: seconds),
  );
  return r ?? SafetyCheckResult.noResponse;
}

class _SafetyCheckDialog extends StatefulWidget {
  final int seconds;
  const _SafetyCheckDialog({required this.seconds});

  @override
  State<_SafetyCheckDialog> createState() => _SafetyCheckDialogState();
}

class _SafetyCheckDialogState extends State<_SafetyCheckDialog> {
  late int left = widget.seconds;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => left--);
      if (left <= 0) {
        _t?.cancel();
        Navigator.pop(context, SafetyCheckResult.noResponse);
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        const IconBadge(Ic.timer, AppColors.lampDeep, size: 56),
        const SizedBox(height: 14),
        const Text('괜찮으세요?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('예상 도착 시간이 지났어요.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.textSub, fontWeight: FontWeight.w500)),
        const SizedBox(height: 14),
        Text('$left초 안에 응답이 없으면 긴급 문자 화면을 열어요',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ProgressLine(value: left / widget.seconds, color: AppColors.danger),
        const SizedBox(height: 18),
        AppButton('괜찮아요 (10분 연장)', icon: Ic.ok, onTap: () => Navigator.pop(context, SafetyCheckResult.ok)),
        const SizedBox(height: 8),
        AppButton('도움이 필요해요',
            icon: Ic.sos, kind: BtnKind.dangerSoft, onTap: () => Navigator.pop(context, SafetyCheckResult.help)),
      ]);
}
