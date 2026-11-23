import 'package:flutter/material.dart';

import '../theme.dart';
import 'app_icons.dart';
import 'kit.dart';

/// 안심디디 공통 부품: 기본 Material 느낌 대신 지도 앱·금융 앱처럼 묶음 카드와 둥근 아이콘 배지를 쓴다.

/// 둥근 사각 배경 위 아이콘
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconBadge(this.icon, this.color, {super.key, this.size = 36});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(size * 0.3)),
        child: Icon(icon, size: size * 0.56, color: color),
      );
}

/// 초록 토글 스위치(기본 Material 스위치 대신, iOS·금융 앱 느낌)
class AppToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const AppToggle({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final off = dark ? const Color(0xFF3A4458) : const Color(0xFFDDE0E6);
    return Semantics(
      toggled: value,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: 50,
            height: 30,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: value ? AppColors.leaf : off, borderRadius: BorderRadius.circular(15)),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(blurRadius: 3, color: Color(0x33000000), offset: Offset(0, 1))],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 묶음 제목 + 둥근 카드
class GroupCard extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const GroupCard({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(Divider(height: 1, thickness: 1, indent: 64, endIndent: 16, color: cs.outlineVariant.withValues(alpha: 0.6)));
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Text(title!, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSub)),
          ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18)),
          child: Column(children: rows),
        ),
      ]),
    );
  }
}

/// 카드 안의 한 줄: 아이콘 배지 · 제목/설명 · 오른쪽(스위치·값·화살표)
class GroupRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  final Color? titleColor;

  const GroupRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.chevron = false,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.985,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(children: [
          IconBadge(icon, color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: titleColor)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.35)),
              ],
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          if (chevron) ...[const SizedBox(width: 6), const Icon(Ic.chevron, size: 16, color: AppColors.textSub)],
        ]),
      ),
    );
  }
}

/// 둥근 회색 칸 안의 작은 글씨(거리·값 표시)
class Pill extends StatelessWidget {
  final String text;
  final Color? color;
  const Pill(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color ?? AppColors.textSub)),
      );
}
