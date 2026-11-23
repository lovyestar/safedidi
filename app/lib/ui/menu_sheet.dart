import 'package:ansim_core/ansim_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'app_icons.dart';
import 'kit.dart';

/// 지도 표시(레이어) 시트: 지도 앱의 '지도 설정'처럼 아이콘 타일을 여러 개 골라 켠다.
/// 켜진 타일 = 초록 테두리, 꺼진 타일 = 연한 회색.
Future<void> showLayerSheet(
  BuildContext context, {
  required bool showHeat,
  required Set<FacilityType> types,
  required void Function(bool heat, Set<FacilityType> types) onChanged,
}) {
  var heat = showHeat;
  final sel = {...types};
  return showAppSheet(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        void changed() {
          setLocal(() {});
          onChanged(heat, sel);
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 2, 20, 2),
              child: Text('지도 표시', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Text('여러 개를 함께 켤 수 있어요', style: TextStyle(fontSize: 12.5, color: AppColors.textSub)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                  child: _LayerTile(
                    icon: Ic.path,
                    label: '도로 밝기',
                    on: heat,
                    onTap: () {
                      heat = !heat;
                      changed();
                    },
                  ),
                ),
                for (final (t, icon) in [
                  (FacilityType.light, Ic.light),
                  (FacilityType.cctv, Ic.cctv),
                  (FacilityType.bell, Ic.bell),
                ]) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _LayerTile(
                      icon: icon,
                      label: t == FacilityType.light ? '보안등' : t.label,
                      on: sel.contains(t),
                      onTap: () {
                        sel.contains(t) ? sel.remove(t) : sel.add(t);
                        changed();
                      },
                    ),
                  ),
                ],
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(children: [
                for (final (c, t) in [(AppColors.leaf, '밝은 길'), (AppColors.lamp, '보통'), (AppColors.danger, '어두운 길')]) ...[
                  Container(width: 14, height: 5, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 5),
                  Text(t, style: const TextStyle(fontSize: 11.5, color: AppColors.textSub, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                ],
              ]),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Text('시설 점은 골목 수준으로 확대하면 보여요.', style: TextStyle(fontSize: 11.5, color: AppColors.textSub)),
            ),
          ]),
        );
      },
    ),
  );
}

class _LayerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _LayerTile({required this.icon, required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final fg = on ? AppColors.leafDeep : AppColors.textSub;
    return Pressable(
      onTap: onTap,
      radius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: on ? AppColors.leaf.withValues(alpha: 0.13) : p.fill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? AppColors.leaf : const Color(0x00000000), width: 1.8),
        ),
        child: Column(children: [
          Icon(icon, color: fg, size: 24),
          const SizedBox(height: 6),
          Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
        ]),
      ),
    );
  }
}
