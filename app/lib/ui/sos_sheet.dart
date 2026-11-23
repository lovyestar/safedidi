import 'package:ansim_core/ansim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import 'app_icons.dart';
import 'guardian_sheet.dart';
import 'kit.dart';
import 'widgets.dart';

String _locationLink(GeoPoint p) =>
    'https://map.kakao.com/link/map/현재위치,${p.lat.toStringAsFixed(6)},${p.lng.toStringAsFixed(6)}';

String sosMessage(GeoPoint? here) =>
    '[안심디디 긴급] 도움이 필요합니다.${here != null ? ' 현재 위치: ${_locationLink(here)}' : ''}';

/// 문자 앱을 위치가 담긴 내용으로 연다(보내기는 사용자가 누른다).
Future<void> openSms(String number, String body) =>
    launchUrl(Uri(scheme: 'sms', path: number, queryParameters: {'body': body}));

/// 안심 타이머 무응답 등: 보호자 연락처가 있으면 보호자, 없으면 112 문자 화면.
Future<void> sendEmergencySms(GeoPoint? here, {String guardianPhone = ''}) =>
    openSms(guardianPhone.isNotEmpty ? guardianPhone : '112', sosMessage(here));

/// 긴급 도움: 112 전화, 112·보호자 문자(현재 위치 포함), 위치 링크 복사.
/// 전화·문자는 기기의 전화/문자 앱을 열 뿐이고, 실제 발신은 사용자가 한다.
Future<void> showSosSheet(BuildContext context, GeoPoint? here, {String guardianPhone = ''}) {
  final body = sosMessage(here);
  return showAppSheet(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const IconBadge(Ic.sos, AppColors.danger, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('긴급 도움', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              Text(here == null ? '현재 위치를 아직 모르지만 바로 신고할 수 있어요' : '현재 위치를 함께 보낼 수 있어요',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSub, fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        AppButton('112 전화하기', icon: Ic.phone, kind: BtnKind.danger, height: 58, onTap: () => launchUrl(Uri(scheme: 'tel', path: '112'))),
        const SizedBox(height: 10),
        AppButton('112 문자 신고 (위치 포함)', icon: Ic.sms, kind: BtnKind.dangerSoft, onTap: () => openSms('112', body)),
        if (guardianPhone.isNotEmpty) ...[
          const SizedBox(height: 10),
          AppButton('보호자에게 문자 (${formatPhone(guardianPhone)})',
              icon: Ic.guardian, kind: BtnKind.secondary, onTap: () => openSms(guardianPhone, body)),
        ],
        if (here != null) ...[
          const SizedBox(height: 10),
          AppButton('위치 링크 복사', icon: Ic.copy, kind: BtnKind.outline, onTap: () async {
            await Clipboard.setData(ClipboardData(text: body));
            if (ctx.mounted) showToast(ctx, '현재 위치 링크를 복사했어요. 가족·친구에게 붙여넣어 보내세요.');
          }),
        ],
      ]),
    ),
  );
}
