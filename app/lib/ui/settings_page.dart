import 'package:ansim_core/ansim_core.dart';
import 'package:flutter/material.dart';

import '../controllers/theme_controller.dart';
import '../data/safety_data.dart';
import '../services/prefs.dart';
import '../theme.dart';
import 'about_page.dart';
import 'app_icons.dart';
import 'guardian_sheet.dart';
import 'kit.dart';
import 'widgets.dart';

/// 설정: 화면 테마 · 안전 기능 · 즐겨찾기 · 정보. 묶음 카드로 직접 그린다.
class SettingsPage extends StatelessWidget {
  final AppPrefs prefs;
  final ThemeController theme;
  final SafetyData data;
  final VoidCallback onSetHome;
  final VoidCallback onSetWork;

  const SettingsPage({
    super.key,
    required this.prefs,
    required this.theme,
    required this.data,
    required this.onSetHome,
    required this.onSetWork,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([prefs, theme]),
          builder: (context, _) => ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            const PageHeader(title: '설정'),
            const SizedBox(height: 6),
            if (prefs.guardianPhone.isEmpty) _GuardianCallout(onTap: () => _editGuardian(context)),
            GroupCard(title: '화면', children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: _ThemePicker(value: theme.choice, isDarkNow: theme.isDark, onChanged: theme.set),
              ),
            ]),
            GroupCard(title: '길 안내 언어', children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: _LangPicker(value: GuideLang.parse(prefs.guideLang), onChanged: (l) => prefs.setGuideLang(l.name)),
              ),
            ]),
            GroupCard(title: '안전 기능', children: [
              GroupRow(
                icon: Ic.guardian,
                color: AppColors.leafDeep,
                title: '보호자 연락처',
                subtitle: prefs.guardianPhone.isEmpty ? '긴급 문자를 보호자에게 먼저 보내요' : formatPhone(prefs.guardianPhone),
                trailing: prefs.guardianPhone.isEmpty ? const Pill('미등록', color: AppColors.danger) : null,
                chevron: true,
                onTap: () => _editGuardian(context),
              ),
              GroupRow(
                icon: Ic.vibrate,
                color: AppColors.danger,
                title: '흔들어서 SOS',
                subtitle: '폰을 세게 3번 흔들면 긴급 도움 화면',
                trailing: AppToggle(value: prefs.shakeSos, onChanged: prefs.setShakeSos),
                onTap: () => prefs.setShakeSos(!prefs.shakeSos),
              ),
              GroupRow(
                icon: Ic.timer,
                color: AppColors.lampDeep,
                title: '안심 타이머',
                subtitle: '예상보다 ${prefs.timerBufferMin}분 넘게 늦으면 안부 확인',
                trailing: AppToggle(value: prefs.safetyTimer, onChanged: prefs.setSafetyTimer),
                onTap: () => prefs.setSafetyTimer(!prefs.safetyTimer),
              ),
            ]),
            GroupCard(title: '즐겨찾기', children: [
              _favRow(context, icon: Ic.home, label: '집', name: prefs.home?.name, onEdit: onSetHome, onClear: () => prefs.setHome(null)),
              _favRow(context, icon: Ic.work, label: '회사', name: prefs.work?.name, onEdit: onSetWork, onClear: () => prefs.setWork(null)),
              GroupRow(
                icon: Ic.recent,
                color: AppColors.textSub,
                title: '최근 검색 기록 삭제',
                subtitle: prefs.recent.isEmpty ? '저장된 기록이 없어요' : '${prefs.recent.length}개 저장됨',
                onTap: prefs.recent.isEmpty
                    ? null
                    : () {
                        prefs.clearRecent();
                        showToast(context, '최근 검색 기록을 지웠어요');
                      },
              ),
            ]),
            GroupCard(title: '정보', children: [
              GroupRow(
                icon: Ic.data,
                color: AppColors.leafDeep,
                title: '데이터 출처·안심지수 계산 방식',
                subtitle: '보안등 ${_comma(data.facilities.countOf(FacilityType.light))} · '
                    'CCTV ${_comma(data.facilities.countOf(FacilityType.cctv))} · '
                    '비상벨 ${_comma(data.facilities.countOf(FacilityType.bell))}',
                chevron: true,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AboutPage(data: data))),
              ),
            ]),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Center(
                child: Text('안심디디 · 부산 밤길 안심 경로',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textSub, fontWeight: FontWeight.w500)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _favRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String? name,
    required VoidCallback onEdit,
    required VoidCallback onClear,
  }) {
    void edit() {
      Navigator.pop(context);
      onEdit();
    }

    return GroupRow(
      icon: icon,
      color: AppColors.leafDeep,
      title: label,
      subtitle: name ?? '눌러서 등록',
      onTap: edit,
      trailing: name == null
          ? const Icon(Ic.plus, size: 20, color: AppColors.leafDeep)
          : CircleBtn.plain(icon: Ic.close, label: '$label 삭제', size: 36, iconSize: 16, fg: AppColors.textSub, onTap: onClear),
    );
  }

  Future<void> _editGuardian(BuildContext context) async {
    final v = await showGuardianSheet(context, initial: prefs.guardianPhone);
    if (v == null) return;
    await prefs.setGuardianPhone(v);
    if (context.mounted) {
      showToast(context, v.isEmpty ? '보호자 연락처를 지웠어요' : '보호자 연락처를 저장했어요 (${formatPhone(v)})');
    }
  }
}

/// 보호자 연락처가 없을 때 맨 위 안내 카드
class _GuardianCallout extends StatelessWidget {
  final VoidCallback onTap;
  const _GuardianCallout({required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        child: Pressable(
          onTap: onTap,
          radius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(color: AppColors.lamp.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
            child: Row(children: [
              const IconBadge(Ic.shield, AppColors.lampDeep, size: 42),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('보호자 연락처를 등록해 두세요', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  SizedBox(height: 2),
                  Text('위급할 때 위치가 담긴 문자를 바로 보낼 수 있어요',
                      style: TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.35)),
                ]),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: AppColors.lamp, borderRadius: BorderRadius.circular(10)),
                child: const Text('등록', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.onLamp)),
              ),
            ]),
          ),
        ),
      );
}

/// 길 안내 언어: 한국어 · English · 日本語 (음성과 안내 화면)
class _LangPicker extends StatelessWidget {
  final GuideLang value;
  final ValueChanged<GuideLang> onChanged;
  const _LangPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    Widget option(GuideLang l, String sample) {
      final on = l == value;
      return Expanded(
        child: Pressable(
          onTap: () => onChanged(l),
          radius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: on ? AppColors.leaf.withValues(alpha: 0.12) : p.fill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: on ? AppColors.leaf : const Color(0x00000000), width: 1.8),
            ),
            child: Column(children: [
              Text(l.nativeName, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: on ? null : AppColors.textSub)),
              const SizedBox(height: 3),
              Text(sample,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: AppColors.textSub, fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        option(GuideLang.ko, '왼쪽 방향입니다'),
        const SizedBox(width: 8),
        option(GuideLang.en, 'Turn left'),
        const SizedBox(width: 8),
        option(GuideLang.ja, '左方向です'),
      ]),
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 10, 4, 0),
        child: Text('길 안내 음성과 안내 화면(위 안내 카드·안내 목록·도착 화면)이 이 언어로 나와요. '
            '영어·일본어에서는 도로 이름을 로마자로 보여줘요.',
            style: TextStyle(fontSize: 12, color: AppColors.textSub, fontWeight: FontWeight.w500, height: 1.4)),
      ),
    ]);
  }
}

/// 자동 · 라이트 · 다크 중 하나 고르기
class _ThemePicker extends StatelessWidget {
  final ThemeChoice value;
  final bool isDarkNow;
  final ValueChanged<ThemeChoice> onChanged;
  const _ThemePicker({required this.value, required this.isDarkNow, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    Widget option(ThemeChoice c, IconData icon, String label, String sub) {
      final on = c == value;
      return Expanded(
        child: Pressable(
          onTap: () => onChanged(c),
          radius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: on ? AppColors.leaf.withValues(alpha: 0.12) : p.fill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: on ? AppColors.leaf : const Color(0x00000000), width: 1.8),
            ),
            child: Column(children: [
              Icon(icon, size: 24, color: on ? AppColors.leafDeep : AppColors.textSub),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? null : AppColors.textSub)),
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(fontSize: 10.5, color: AppColors.textSub, fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        option(ThemeChoice.auto, Ic.auto, '자동', '18시~7시 다크'),
        const SizedBox(width: 8),
        option(ThemeChoice.light, Ic.sun, '라이트', '밝은 지도'),
        const SizedBox(width: 8),
        option(ThemeChoice.dark, Ic.moon, '다크', '어두운 지도'),
      ]),
      if (value == ThemeChoice.auto)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
          child: Text('지금은 ${isDarkNow ? '다크' : '라이트'} 화면이에요',
              style: const TextStyle(fontSize: 12, color: AppColors.textSub, fontWeight: FontWeight.w500)),
        ),
    ]);
  }
}

String _comma(int v) => v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
