import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'app_icons.dart';

/// 안심디디 자체 디자인 부품. 머티리얼 기본 버튼·물결·스낵바·대화창·시트 모양을 쓰지 않는다.
/// 레퍼런스: 네이버 지도 도보 안내(위 안내 카드·아래 요약 막대), 워크온(둥근 흰 카드·부드러운 그림자).

// ── 색·그림자 ───────────────────────────────────────────────
class Pal {
  final bool dark;
  const Pal(this.dark);
  static Pal of(BuildContext c) => Pal(Theme.of(c).brightness == Brightness.dark);

  Color get bg => dark ? AppColors.night : AppColors.day;
  Color get surface => dark ? AppColors.nightSurface : Colors.white;
  Color get fill => dark ? AppColors.nightSurfaceHigh : AppColors.dayFill;
  Color get line => dark ? AppColors.nightLine : AppColors.dayLine;
  Color get text => dark ? const Color(0xFFE8EEE9) : const Color(0xFF18201B);
  Color get sub => AppColors.textSub;

  /// 눌렀을 때 덮는 색
  Color get press => dark ? const Color(0x14FFFFFF) : const Color(0x0D0B1A10);

  List<BoxShadow> get soft => [
        BoxShadow(color: dark ? const Color(0x59000000) : const Color(0x120B1A10), blurRadius: 18, offset: const Offset(0, 6)),
      ];

  List<BoxShadow> get float => [
        BoxShadow(color: dark ? const Color(0x80000000) : const Color(0x210B1A10), blurRadius: 22, offset: const Offset(0, 8)),
        BoxShadow(color: dark ? const Color(0x40000000) : const Color(0x0F0B1A10), blurRadius: 4, offset: const Offset(0, 1)),
      ];
}

// ── 누름 효과(물결 대신 살짝 줄어들고 옅게 덮임) ─────────────────
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final BorderRadius? radius;
  final bool overlay;
  final String? label;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.radius,
    this.overlay = true,
    this.label,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    Widget child = widget.child;
    if (widget.overlay) {
      child = AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        foregroundDecoration: BoxDecoration(
          color: _down ? Pal.of(context).press : const Color(0x00000000),
          borderRadius: widget.radius,
        ),
        child: child,
      );
    }
    return Semantics(
      button: enabled,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                _set(false);
                widget.onLongPress!();
              },
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: child,
        ),
      ),
    );
  }
}

// ── 버튼 ────────────────────────────────────────────────────
enum BtnKind {
  /// 가로등 노랑(주요 동작)
  primary,

  /// 안심 초록
  leaf,

  /// 연한 회색 면
  secondary,

  /// 테두리만
  outline,

  /// 빨강(SOS)
  danger,

  /// 연한 빨강 면
  dangerSoft,
}

class AppButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final BtnKind kind;
  final double height;
  final bool expand;

  const AppButton(
    this.label, {
    super.key,
    this.icon,
    this.onTap,
    this.kind = BtnKind.primary,
    this.height = 54,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final (bg, fg, border) = switch (kind) {
      BtnKind.primary => (AppColors.lamp, AppColors.onLamp, null),
      BtnKind.leaf => (AppColors.leafDeep, Colors.white, null),
      BtnKind.secondary => (p.fill, p.text, null),
      BtnKind.outline => (p.surface, p.text, p.line),
      BtnKind.danger => (AppColors.danger, Colors.white, null),
      BtnKind.dangerSoft => (AppColors.danger.withValues(alpha: 0.12), AppColors.danger, null),
    };
    final small = height < 46;
    final body = Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: small ? 14 : 18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(small ? 12 : 16),
        border: border == null ? null : Border.all(color: border, width: 1.2),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: small ? 17 : 20, color: fg), SizedBox(width: small ? 6 : 8)],
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: small ? 13.5 : 15, fontWeight: FontWeight.w700, color: fg)),
          ),
        ],
      ),
    );
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Pressable(onTap: onTap, radius: BorderRadius.circular(small ? 12 : 16), label: label, child: body),
    );
  }
}

/// 둥근 아이콘 버튼(지도 위 버튼·헤더 버튼)
class CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? bg;
  final Color? fg;
  final bool shadow;
  final String? label;
  final double? iconSize;

  const CircleBtn({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 46,
    this.bg,
    this.fg,
    this.shadow = true,
    this.label,
    this.iconSize,
  });

  /// 배경 없는 헤더용(뒤로·닫기)
  const CircleBtn.plain({super.key, required this.icon, this.onTap, this.size = 44, this.fg, this.label, this.iconSize})
      : bg = const Color(0x00000000),
        shadow = false;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Pressable(
      onTap: onTap,
      scale: 0.92,
      radius: BorderRadius.circular(size),
      label: label,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg ?? p.surface, shape: BoxShape.circle, boxShadow: shadow ? p.float : null),
        child: Icon(icon, size: iconSize ?? size * 0.46, color: fg ?? p.text),
      ),
    );
  }
}

/// 글자 버튼(전체 삭제 등)
class TextLink extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final Color? color;
  const TextLink(this.text, {super.key, this.onTap, this.color});

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        overlay: false,
        scale: 0.94,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Text(text,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color ?? AppColors.textSub)),
        ),
      );
}

// ── 카드·제목·줄 ─────────────────────────────────────────────
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final bool shadow;
  final bool border;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.color,
    this.shadow = false,
    this.border = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? p.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow ? p.soft : null,
        border: border ? Border.all(color: p.line) : null,
      ),
      child: child,
    );
    return onTap == null ? box : Pressable(onTap: onTap, radius: BorderRadius.circular(radius), child: box);
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  const SectionTitle(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(20, 22, 14, 10)});

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          ?trailing,
        ]),
      );
}

class Hairline extends StatelessWidget {
  final double indent;
  final double endIndent;
  const Hairline({super.key, this.indent = 0, this.endIndent = 0});

  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: EdgeInsets.only(left: indent, right: endIndent),
        color: Pal.of(context).line.withValues(alpha: 0.8),
      );
}

/// 시트 맨 위 손잡이
class Grabber extends StatelessWidget {
  const Grabber({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.only(top: 10, bottom: 8),
          width: 38,
          height: 5,
          decoration: BoxDecoration(color: Pal.of(context).line, borderRadius: BorderRadius.circular(3)),
        ),
      );
}

/// 페이지 머리줄(머티리얼 AppBar 대신)
class PageHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  const PageHeader({super.key, required this.title, this.onBack, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
        child: Row(children: [
          CircleBtn.plain(icon: Ic.back, label: '뒤로', onTap: onBack ?? () => Navigator.of(context).maybePop()),
          const SizedBox(width: 4),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          ?trailing,
        ]),
      );
}

// ── 입력칸 ──────────────────────────────────────────────────
class AppTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final bool autofocus;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? error;
  final bool large;

  const AppTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.icon,
    this.autofocus = false,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.error,
    this.large = false,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    widget.controller.addListener(_onText);
  }

  void _onText() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final err = widget.error != null;
    final borderColor = err ? AppColors.danger : (_focus.hasFocus ? AppColors.leaf : const Color(0x00000000));
    final size = widget.large ? 18.0 : 15.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: widget.large ? 58 : 50,
        padding: const EdgeInsets.only(left: 14, right: 6),
        decoration: BoxDecoration(
          color: p.fill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1.6),
        ),
        child: Row(children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 20, color: _focus.hasFocus ? AppColors.leafDeep : p.sub),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              inputFormatters: widget.inputFormatters,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              cursorColor: AppColors.leafDeep,
              cursorWidth: 2,
              cursorRadius: const Radius.circular(2),
              style: TextStyle(fontSize: size, fontWeight: widget.large ? FontWeight.w700 : FontWeight.w500, color: p.text),
              decoration: InputDecoration.collapsed(
                hintText: widget.hint,
                hintStyle: TextStyle(fontSize: size, fontWeight: FontWeight.w500, color: p.sub),
              ),
            ),
          ),
          if (widget.controller.text.isNotEmpty)
            CircleBtn.plain(
              icon: Ic.clear,
              size: 38,
              iconSize: 19,
              fg: p.sub,
              label: '지우기',
              onTap: () {
                widget.controller.clear();
                widget.onChanged?.call('');
              },
            ),
        ]),
      ),
      if (err)
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
          child: Text(widget.error!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.danger)),
        ),
    ]);
  }
}

// ── 불러오는 중 표시(가로등 노랑 → 안심 초록 호) ─────────────────
class LampSpinner extends StatefulWidget {
  final double size;
  final double stroke;
  const LampSpinner({super.key, this.size = 22, this.stroke = 3});

  @override
  State<LampSpinner> createState() => _LampSpinnerState();
}

class _LampSpinnerState extends State<LampSpinner> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(painter: _ArcPainter(_c.value, widget.stroke, Pal.of(context).line)),
        ),
      );
}

class _ArcPainter extends CustomPainter {
  final double t;
  final double stroke;
  final Color track;
  _ArcPainter(this.t, this.stroke, this.track);

  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromLTWH(stroke / 2, stroke / 2, s.width - stroke, s.height - stroke);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track);
    final start = t * math.pi * 2;
    canvas.drawArc(
      r,
      start,
      math.pi * 0.8,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: start,
          endAngle: start + math.pi * 0.8,
          colors: const [AppColors.lamp, AppColors.leaf],
          transform: GradientRotation(start),
        ).createShader(r),
    );
  }

  @override
  bool shouldRepaint(covariant _ArcPainter old) => old.t != t || old.track != track;
}

/// 얇은 진행 막대
class ProgressLine extends StatelessWidget {
  final double value;
  final double height;
  final Color color;
  const ProgressLine({super.key, required this.value, this.height = 6, this.color = AppColors.leaf});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Container(
          height: height,
          color: Pal.of(context).fill,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(color: color),
          ),
        ),
      );
}

// ── 바닥 시트·대화창·알림(머티리얼 모양 대신) ─────────────────────
/// 아래에서 올라오는 시트. 손잡이를 끌어내리거나 바깥을 누르면 닫힌다.
Future<T?> showAppSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '닫기',
    barrierColor: const Color(0x73000000),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, _, _) => Align(alignment: Alignment.bottomCenter, child: _SheetFrame(child: builder(ctx))),
    transitionBuilder: (ctx, a, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero)
          .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
      child: child,
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  final Widget child;
  const _SheetFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final mq = MediaQuery.of(context);
    return GestureDetector(
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 500) Navigator.of(context).maybePop();
      },
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
          padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Grabber(),
              Flexible(child: child),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 가운데 대화창(AlertDialog 대신)
Future<T?> showAppDialog<T>(BuildContext context, {required WidgetBuilder builder, bool dismissible = true}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: '닫기',
    barrierColor: const Color(0x8C000000),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) => Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
            decoration: BoxDecoration(color: Pal.of(ctx).surface, borderRadius: BorderRadius.circular(26)),
            child: builder(ctx),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, a, _, child) {
      final c = CurvedAnimation(parent: a, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(c), child: child),
      );
    },
  );
}

/// 화면 아래 잠깐 뜨는 알림(SnackBar 대신)
OverlayEntry? _toast;
Timer? _toastTimer;

void showToast(BuildContext context, String message, {IconData? icon, String? action, VoidCallback? onAction}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _toastTimer?.cancel();
  _toast?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _Toast(
      message: message,
      icon: icon,
      action: action,
      onAction: onAction == null
          ? null
          : () {
              onAction();
              if (_toast == entry) {
                entry.remove();
                _toast = null;
              }
            },
    ),
  );
  _toast = entry;
  overlay.insert(entry);
  _toastTimer = Timer(Duration(milliseconds: action == null ? 2600 : 4500), () {
    if (_toast == entry) {
      entry.remove();
      _toast = null;
    }
  });
}

class _Toast extends StatefulWidget {
  final String message;
  final IconData? icon;
  final String? action;
  final VoidCallback? onAction;
  const _Toast({required this.message, this.icon, this.action, this.onAction});

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return Positioned(
      left: 16,
      right: 16,
      bottom: mq.viewInsets.bottom + mq.viewPadding.bottom + 22,
      child: FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(curve),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 13, 10, 13),
              decoration: BoxDecoration(
                color: const Color(0xF2202A24),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 6))],
              ),
              child: Row(children: [
                Icon(widget.icon ?? Ic.ok, size: 20, color: AppColors.leaf),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(widget.message,
                      style: const TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w500, color: Colors.white)),
                ),
                if (widget.action != null)
                  TextLink(widget.action!, onTap: widget.onAction, color: AppColors.lamp),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
