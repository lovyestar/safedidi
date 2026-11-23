import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'app_icons.dart';
import 'kit.dart';
import 'widgets.dart';

/// 숫자만 받아 010-1234-5678 / 02-123-4567 형태로 하이픈을 넣는다.
String formatPhone(String digits) {
  final d = digits.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('02')) {
    if (d.length <= 2) return d;
    if (d.length <= 5) return '${d.substring(0, 2)}-${d.substring(2)}';
    if (d.length <= 9) return '${d.substring(0, 2)}-${d.substring(2, 5)}-${d.substring(5)}';
    return '${d.substring(0, 2)}-${d.substring(2, 6)}-${d.substring(6, d.length.clamp(6, 10))}';
  }
  if (d.length <= 3) return d;
  if (d.length <= 6) return '${d.substring(0, 3)}-${d.substring(3)}';
  if (d.length <= 10) return '${d.substring(0, 3)}-${d.substring(3, 6)}-${d.substring(6)}';
  return '${d.substring(0, 3)}-${d.substring(3, 7)}-${d.substring(7, d.length.clamp(7, 11))}';
}

bool isValidPhone(String s) => RegExp(r'^0\d{8,10}$').hasMatch(s.replaceAll(RegExp(r'\D'), ''));

class _PhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final f = formatPhone(newValue.text);
    return TextEditingValue(text: f, selection: TextSelection.collapsed(offset: f.length));
  }
}

/// 보호자 연락처 입력 시트. 저장하면 숫자만, 삭제하면 '' 를 돌려준다. 취소면 null.
Future<String?> showGuardianSheet(BuildContext context, {String initial = ''}) =>
    showAppSheet<String>(context, builder: (ctx) => _GuardianSheet(initial: initial));

class _GuardianSheet extends StatefulWidget {
  final String initial;
  const _GuardianSheet({required this.initial});

  @override
  State<_GuardianSheet> createState() => _GuardianSheetState();
}

class _GuardianSheetState extends State<_GuardianSheet> {
  late final _ctrl = TextEditingController(text: formatPhone(widget.initial));
  bool _touched = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = isValidPhone(_ctrl.text);
    final showError = _touched && _ctrl.text.isNotEmpty && !valid;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          IconBadge(Ic.guardian, AppColors.leafDeep, size: 42),
          SizedBox(width: 12),
          Text('보호자 연락처', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        const Text(
          '위급할 때·안심 타이머에 응답이 없을 때 이 번호로 보낼 문자 화면을 바로 열어요.\n번호는 이 폰에만 저장돼요.',
          style: TextStyle(fontSize: 12.5, color: AppColors.textSub, height: 1.5, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 18),
        AppTextField(
          controller: _ctrl,
          hint: '010-1234-5678',
          icon: Ic.phone,
          large: true,
          autofocus: true,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')), _PhoneFormatter()],
          onChanged: (_) => setState(() => _touched = true),
          error: showError ? '전화번호를 다시 확인해 주세요' : null,
        ),
        const SizedBox(height: 18),
        Row(children: [
          if (widget.initial.isNotEmpty) ...[
            Expanded(child: AppButton('삭제', kind: BtnKind.dangerSoft, onTap: () => Navigator.pop(context, ''))),
            const SizedBox(width: 10),
          ],
          Expanded(
            flex: 2,
            child: AppButton('저장', onTap: valid ? () => Navigator.pop(context, _ctrl.text.replaceAll(RegExp(r'\D'), '')) : null),
          ),
        ]),
      ]),
    );
  }
}
