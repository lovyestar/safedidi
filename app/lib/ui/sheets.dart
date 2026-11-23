import 'dart:math' as math;

import 'package:ansim_core/ansim_core.dart';
import 'package:flutter/material.dart';

import '../controllers/route_controller.dart';
import '../data/area_safety.dart';
import '../services/kakao_local.dart';
import '../services/night_tools.dart';
import '../services/prefs.dart';
import '../services/safe_places.dart';
import '../theme.dart';
import 'app_icons.dart';
import 'guidance_widgets.dart';
import 'guide_text.dart';
import 'kit.dart';
import 'map_layers.dart';
import 'widgets.dart';

/// 지도 아래 끌어올리는 시트들. 모두 ui/kit.dart의 자체 부품으로 그린다.

String _comma(int v) => v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

// ── 홈: 내 주변 안심 · 집/회사 · 최근 검색 ────────────────────────
class HomeSheet extends StatelessWidget {
  final ScrollController scroll;
  final AppPrefs prefs;
  final FacilityStore facilities;
  final AreaSafety? area;
  final String? areaName;
  final void Function(PlaceRef) onGo;
  final VoidCallback onSetHome;
  final VoidCallback onSetWork;

  const HomeSheet({
    super.key,
    required this.scroll,
    required this.prefs,
    required this.facilities,
    required this.area,
    required this.areaName,
    required this.onGo,
    required this.onSetHome,
    required this.onSetWork,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => ListView(
        controller: scroll,
        padding: EdgeInsets.zero,
        children: [
          const Grabber(),
          if (area != null)
            Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 0), child: AreaCard(area: area!, areaName: areaName)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              Expanded(
                child: _QuickPlace(
                  icon: Ic.home,
                  label: '집',
                  place: prefs.home,
                  onTap: prefs.home == null ? onSetHome : () => onGo(prefs.home!),
                  onLongPress: onSetHome,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickPlace(
                  icon: Ic.work,
                  label: '회사',
                  place: prefs.work,
                  onTap: prefs.work == null ? onSetWork : () => onGo(prefs.work!),
                  onLongPress: onSetWork,
                ),
              ),
            ]),
          ),
          SectionTitle('최근 검색',
              trailing: prefs.recent.isEmpty ? null : TextLink('전체 삭제', onTap: prefs.clearRecent)),
          if (prefs.recent.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('검색한 장소가 여기에 쌓여요.', style: TextStyle(fontSize: 12.5, color: AppColors.textSub)),
            ),
          // 왼쪽으로 밀어서 하나씩 지우기(지도 앱과 같은 동작)
          for (final p in prefs.recent)
            Dismissible(
              key: ValueKey('${p.name}@${p.point.lat},${p.point.lng}'),
              direction: DismissDirection.endToStart,
              onDismissed: (_) => prefs.removeRecent(p),
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                color: AppColors.danger,
                child: const Icon(Ic.trash, color: Colors.white),
              ),
              child: PlaceLine(
                icon: Ic.recent,
                color: AppColors.textSub,
                title: p.name,
                subtitle: p.address,
                onTap: () => onGo(p),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            child: Text(
              '부산 보안등 ${_comma(facilities.countOf(FacilityType.light))} · '
              'CCTV ${_comma(facilities.countOf(FacilityType.cctv))} · '
              '비상벨 ${_comma(facilities.countOf(FacilityType.bell))} 공공데이터 기반',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textSub, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// 내 주변 안심지수 카드: 점수 고리 + 주변 시설 수. 점수에 따라 초록·노랑·주황 면.
class AreaCard extends StatelessWidget {
  final AreaSafety area;
  final String? areaName;
  const AreaCard({super.key, required this.area, this.areaName});

  @override
  Widget build(BuildContext context) {
    final s = area.score;
    final (c1, c2, fg) = s >= 60
        ? (AppColors.leaf, AppColors.leafDeep, Colors.white)
        : s >= 40
            ? (const Color(0xFFFFCF3F), AppColors.lamp, AppColors.onLamp)
            : (const Color(0xFFFF8A4C), const Color(0xFFF2564A), Colors.white);
    final sub = fg.withValues(alpha: 0.78);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c1, c2], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(areaName == null ? '지금 내 주변' : '지금 내 주변 · $areaName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: sub)),
            const SizedBox(height: 2),
            Text.rich(TextSpan(children: [
              TextSpan(text: '밤길 ', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: fg)),
              TextSpan(text: scoreLabel(s), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: fg)),
            ])),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 4, children: [
              _mini(Ic.light, '보안등 ${area.lights}', fg),
              _mini(Ic.cctv, 'CCTV ${area.cctvs}', fg),
              _mini(Ic.bell, '비상벨 ${area.bells}', fg),
            ]),
            const SizedBox(height: 4),
            Text('반경 ${area.radiusM.round()}m', style: TextStyle(fontSize: 11, color: sub, fontWeight: FontWeight.w500)),
          ]),
        ),
        const SizedBox(width: 12),
        ScoreRing(score: s, color: fg, size: 78),
      ]),
    );
  }

  Widget _mini(IconData icon, String text, Color fg) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: fg),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
      ]);
}

/// 0~100 점수 고리
class ScoreRing extends StatelessWidget {
  final int score;
  final Color color;
  final double size;
  const ScoreRing({super.key, required this.score, required this.color, this.size = 72});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(score / 100, color),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$score', style: TextStyle(fontSize: size * 0.32, height: 1, fontWeight: FontWeight.w700, color: color)),
              Text('안심지수', style: TextStyle(fontSize: size * 0.12, fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.8))),
            ]),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color color;
  _RingPainter(this.v, this.color);

  @override
  void paint(Canvas canvas, Size s) {
    const w = 6.0;
    final r = Rect.fromLTWH(w / 2, w / 2, s.width - w, s.height - w);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..color = color.withValues(alpha: 0.22));
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * v.clamp(0.0, 1.0), false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..color = color);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.v != v || old.color != color;
}

class _QuickPlace extends StatelessWidget {
  final IconData icon;
  final String label;
  final PlaceRef? place;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _QuickPlace(
      {required this.icon, required this.label, required this.place, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      radius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(color: p.fill, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          IconBadge(icon, AppColors.leafDeep, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              Text(place?.name ?? '등록하기',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      color: place == null ? AppColors.leafDeep : AppColors.textSub,
                      fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// 장소 한 줄(최근 검색·안전 장소)
class PlaceLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const PlaceLine(
      {super.key, required this.icon, required this.color, required this.title, this.subtitle, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        scale: 0.985,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
          child: Row(children: [
            IconBadge(icon, color, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSub, fontWeight: FontWeight.w500)),
                ],
              ]),
            ),
            ?trailing,
          ]),
        ),
      );
}

// ── 장소 카드(검색 결과·지도 길게 누르기) ──────────────────────────
class PlaceSheet extends StatelessWidget {
  final ScrollController scroll;
  final PlaceRef place;
  final double? fromMeM;
  final AreaSafety? area;
  final VoidCallback onOrigin;
  final VoidCallback onDestination;
  final VoidCallback onClose;

  const PlaceSheet({
    super.key,
    required this.scroll,
    required this.place,
    required this.fromMeM,
    required this.area,
    required this.onOrigin,
    required this.onDestination,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final info = [if (place.category != null) place.category!, if (fromMeM != null) '내 위치에서 ${fmtDist(fromMeM!)}'];
    return ListView(controller: scroll, padding: EdgeInsets.zero, children: [
      const Grabber(),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 10, 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(place.name, style: const TextStyle(fontSize: 19, height: 1.25, fontWeight: FontWeight.w700)),
              if (info.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(info.join(' · '),
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textSub, fontWeight: FontWeight.w500)),
              ],
              if (place.address != null) ...[
                const SizedBox(height: 2),
                Text(place.address!, style: TextStyle(fontSize: 12.5, color: p.text.withValues(alpha: 0.8))),
              ],
            ]),
          ),
          CircleBtn.plain(icon: Ic.close, label: '닫기', onTap: onClose),
        ]),
      ),
      if (area != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: AppCard(
            color: p.fill,
            radius: 18,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(children: [
              ScoreRing(score: area!.score, color: scoreInk(area!.score / 100, Theme.of(context).brightness), size: 54),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('이 근처 밤길 ${scoreLabel(area!.score)}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text('반경 ${area!.radiusM.round()}m 보안등 ${area!.lights} · CCTV ${area!.cctvs} · 비상벨 ${area!.bells}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSub, fontWeight: FontWeight.w500)),
                ]),
              ),
            ]),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Row(children: [
          Expanded(child: AppButton('출발', icon: Ic.walk, kind: BtnKind.secondary, onTap: onOrigin)),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: AppButton('도착 · 안심 길찾기', icon: Ic.navigate, onTap: onDestination)),
        ]),
      ),
    ]);
  }
}

// ── 경로 결과: 안심/최단 비교 + 길 안내 목록 + 안내 시작(아래 고정) ──────
class RouteSheet extends StatelessWidget {
  final ScrollController scroll;
  final RouteController rc;
  final VoidCallback onStart;
  final void Function(SafePlace) onPlaceTap;

  const RouteSheet({super.key, required this.scroll, required this.rc, required this.onStart, required this.onPlaceTap});

  @override
  Widget build(BuildContext context) {
    final plan = rc.plan!;
    final c = plan.comparison;
    final p = Pal.of(context);
    final active = rc.activeRoute!;
    final safeOn = rc.safeSelected || c.identical;
    final showDelta = safeOn && !c.identical;
    final tmap = plan.generalSource == GeneralRouteSource.tmap;
    final steps = rc.maneuversOf(active);
    return Column(children: [
      Expanded(
        child: ListView(
          controller: scroll,
          padding: EdgeInsets.zero,
          children: [
            const Grabber(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: c.identical
                  ? _RouteOption(title: '추천 경로', tag: '최단 = 안심', m: c.safe, selected: true, color: AppColors.leaf)
                  : IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(
                          child: _RouteOption(
                            title: '안심 경로',
                            tag: '추천',
                            m: c.safe,
                            selected: rc.safeSelected,
                            color: AppColors.leaf,
                            onTap: () => rc.selectRoute(safe: true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _RouteOption(
                            // TMAP 경로가 안심 경로보다 길면 '최단'이 아니므로 'TMAP 경로'라고 부른다
                            title: rc.generalName,
                            caption: c.safeIsShorter ? null : (tmap ? 'TMAP' : '직접 계산'),
                            m: c.general,
                            selected: !rc.safeSelected,
                            color: AppColors.plain,
                            onTap: () => rc.selectRoute(safe: false),
                          ),
                        ),
                      ]),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _Summary(text: safeOn ? c.message : _generalNote(c), good: safeOn),
            ),
            const SectionTitle('구간 밝기'),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: BrightnessBar(metrics: active)),
            const SectionTitle('경로 주변 안전시설'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                _Stat(icon: Ic.light, color: AppColors.lampDeep, label: '보안등', value: active.tally.lights, delta: showDelta ? c.extraLights : 0),
                const SizedBox(width: 8),
                _Stat(icon: Ic.cctv, color: AppColors.cctv, label: 'CCTV', value: active.tally.cctvs, delta: showDelta ? c.extraCctvs : 0),
                const SizedBox(width: 8),
                _Stat(icon: Ic.bell, color: AppColors.bell, label: '비상벨', value: active.tally.bells, delta: showDelta ? c.extraBells : 0),
              ]),
            ),
            SectionTitle('길 안내', trailing: Pill('${math.max(0, steps.length - 2)}곳')),
            ...maneuverTiles(steps, destName: rc.destination?.name, lang: rc.lang),
            SectionTitle('위급할 때 들를 곳', trailing: Pill('${rc.safePlaces.length}곳')),
            if (rc.safePlaces.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text('경로 150m 안에 찾은 편의점·지구대가 없어요.', style: TextStyle(fontSize: 12.5, color: AppColors.textSub)),
              ),
            for (final sp in rc.safePlaces.take(6))
              PlaceLine(
                icon: safeKindIcon(sp.kind),
                color: safeKindColor(sp.kind),
                title: sp.name,
                subtitle: '${sp.kind.label} · 경로에서 ${sp.fromRouteM.round()}m',
                trailing: const Icon(Ic.chevron, size: 16, color: AppColors.textSub),
                onTap: () => onPlaceTap(sp),
              ),
            if (rc.notice != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Text(rc.notice!, style: const TextStyle(fontSize: 11.5, color: AppColors.textSub, height: 1.4)),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      // 안내 시작: 시트를 얼마나 올렸든 항상 보이게 아래에 고정
      Container(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.viewPaddingOf(context).bottom),
        decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.line))),
        child: AppButton(safeOn ? '안심 경로로 안내 시작' : '${rc.generalName}로 안내 시작', icon: Ic.navigate, onTap: onStart),
      ),
    ]);
  }

  static String _generalNote(RouteComparison c) {
    final dark = c.darkAvoided > 0 ? ' 어두운 구간도 ${c.darkAvoided}곳 더 지나요.' : '';
    // TMAP 경로가 안심 경로보다 긴 경우: '가장 빠른 길'이 아니다
    if (c.safeIsShorter) {
      final min = c.extraMinutes < 0 ? '(${-c.extraMinutes}분)' : '';
      final score = c.scoreGain > 0 ? '안심지수도 ${c.scoreGain}점 낮아요.' : '밝기는 비슷해요.';
      return '안심 경로보다 ${-c.extraMeters}m$min 더 걷는 길이고, $score$dark';
    }
    if (c.scoreGain <= 0) return '가장 빠른 길이에요. 안심 경로와 밝기가 비슷해요.';
    return '가장 빠른 길이지만 안심 경로보다 안심지수가 ${c.scoreGain}점 낮아요.$dark';
  }
}

/// 경로 선택 카드: 이름·시간·거리·구간 밝기 미니 막대·안심지수
class _RouteOption extends StatelessWidget {
  final String title;
  final String? tag;
  final String? caption;
  final RouteMetrics m;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;
  const _RouteOption({
    required this.title,
    this.tag,
    this.caption,
    required this.m,
    required this.selected,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final ink = scoreInk(m.avgScore, Theme.of(context).brightness);
    return Pressable(
      onTap: onTap,
      radius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.10) : p.fill,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? color : const Color(0x00000000), width: 2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: selected ? null : AppColors.textSub)),
            ),
            if (tag != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                child: Text(tag!, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ],
            if (caption != null) ...[
              const SizedBox(width: 6),
              Text(caption!, style: const TextStyle(fontSize: 10.5, color: AppColors.textSub, fontWeight: FontWeight.w500)),
            ],
          ]),
          const SizedBox(height: 6),
          Text.rich(TextSpan(children: [
            TextSpan(text: '${m.minutes}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.1)),
            const TextSpan(text: '분', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            TextSpan(
              text: '  ${fmtDist(m.distanceM)}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSub, fontWeight: FontWeight.w500),
            ),
          ])),
          const SizedBox(height: 10),
          _SegmentBar(metrics: m, height: 5),
          const SizedBox(height: 8),
          Text.rich(TextSpan(children: [
            const TextSpan(text: '안심지수 ', style: TextStyle(fontSize: 12, color: AppColors.textSub, fontWeight: FontWeight.w500)),
            TextSpan(text: '${m.safetyScore}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink)),
            TextSpan(text: ' ${scoreLabel(m.safetyScore)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ink)),
          ])),
        ]),
      ),
    );
  }
}

/// 경로를 왜 추천하는지 한두 줄
class _Summary extends StatelessWidget {
  final String text;
  final bool good;
  const _Summary({required this.text, required this.good});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
        decoration: BoxDecoration(
          color: (good ? AppColors.leaf : AppColors.plain).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(good ? Ic.shield : Ic.info, size: 18, color: good ? AppColors.leafDeep : AppColors.textSub),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.45, fontWeight: FontWeight.w500))),
        ]),
      );
}

/// 경로 주변 시설 수(+안심 경로가 더 지나는 수)
class _Stat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int value;
  final int delta;
  const _Stat({required this.icon, required this.color, required this.label, required this.value, this.delta = 0});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(color: Pal.of(context).fill, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textSub, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(_comma(value), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              if (delta > 0) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: Text('+$delta',
                      maxLines: 1, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.leafDeep)),
                ),
              ],
            ]),
          ]),
        ),
      );
}

Map<Brightness3, int> _brightnessCounts(RouteMetrics m) {
  final counts = {for (final b in Brightness3.values) b: 0};
  for (final s in m.sampleScores.skip(1)) {
    counts[brightnessOf(s)] = counts[brightnessOf(s)]! + 1;
  }
  return counts;
}

/// 밝음·보통·어두움 비율 막대
class _SegmentBar extends StatelessWidget {
  final RouteMetrics metrics;
  final double height;
  const _SegmentBar({required this.metrics, this.height = 8});

  @override
  Widget build(BuildContext context) {
    final counts = _brightnessCounts(metrics);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Row(children: [
          for (final b in Brightness3.values)
            if (counts[b]! > 0) Expanded(flex: counts[b]!, child: Container(color: brightnessColor(b))),
        ]),
      ),
    );
  }
}

/// 경로의 밝음·보통·어두움 비율 막대 + 범례(지도 앱의 교통 막대처럼).
class BrightnessBar extends StatelessWidget {
  final RouteMetrics metrics;
  const BrightnessBar({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final counts = _brightnessCounts(metrics);
    final total = counts.values.fold(0, (a, b) => a + b).clamp(1, 1 << 30);
    final pct = {for (final e in counts.entries) e.key: (e.value * 100 / total).round()};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SegmentBar(metrics: metrics, height: 10),
      const SizedBox(height: 8),
      Row(children: [
        _legend(Brightness3.bright, '밝음', pct[Brightness3.bright]!),
        _legend(Brightness3.normal, '보통', pct[Brightness3.normal]!),
        _legend(Brightness3.dark, '어두움', pct[Brightness3.dark]!),
      ]),
    ]);
  }

  Widget _legend(Brightness3 b, String label, int pct) => Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: brightnessColor(b), shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textSub, fontWeight: FontWeight.w500)),
          const SizedBox(width: 3),
          Text('$pct%', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
        ]),
      );
}

// ── 안내 중: 남은 시간·거리·도착 시각 + 진행 막대 + 도구 + 전체 안내 ─────────
class NavSheet extends StatelessWidget {
  final ScrollController scroll;
  final RouteController rc;
  final NightTools night;
  final VoidCallback onTorch;
  final VoidCallback onStop;

  const NavSheet(
      {super.key, required this.scroll, required this.rc, required this.night, required this.onTorch, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final score = rc.hereScore;
    final pct = score == null ? null : (score * 100).round();
    final deadline = rc.timerDeadline;
    final route = rc.activeRoute;
    final total = route?.distanceM ?? 1;
    final eta = rc.eta;
    final t = GuideText.of(rc.lang);
    return ListView(
      controller: scroll,
      padding: EdgeInsets.zero,
      children: [
        const Grabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: rc.remainingM == null
                  ? Text(t.locating, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text.rich(TextSpan(children: [
                        TextSpan(text: '${rc.remainingMin}', style: const TextStyle(fontSize: 27, height: 1.1, fontWeight: FontWeight.w700)),
                        TextSpan(text: '${t.minUnit}  ', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        TextSpan(
                            text: fmtDist(rc.remainingM!),
                            style: const TextStyle(fontSize: 15, color: AppColors.textSub, fontWeight: FontWeight.w600)),
                      ])),
                      if (eta != null)
                        Text(t.eta(eta),
                            style: const TextStyle(fontSize: 12.5, color: AppColors.textSub, fontWeight: FontWeight.w600)),
                    ]),
            ),
            if (pct != null)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                decoration: BoxDecoration(color: Pal.of(context).fill, borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(t.hereNow, style: const TextStyle(fontSize: 11, color: AppColors.textSub, fontWeight: FontWeight.w600)),
                  // 경로 선 색과 같은 3단계(밝음·보통·어두움)로 표시
                  Text('$pct · ${t.brightness(brightnessOf(score!))}',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: brightnessInk(brightnessOf(score), Theme.of(context).brightness))),
                ]),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: ProgressLine(value: rc.remainingM == null ? 0 : 1 - rc.remainingM! / total),
        ),
        if (deadline != null || rc.rerouteCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Wrap(spacing: 12, runSpacing: 4, children: [
              if (deadline != null)
                _InfoLine(Ic.timer, t.timerUntil(deadline)),
              if (rc.rerouteCount > 0) _InfoLine(Ic.refresh, t.rerouted(rc.rerouteCount)),
            ]),
          ),
        if (rc.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Text(rc.error!, style: const TextStyle(fontSize: 12, color: AppColors.danger, fontWeight: FontWeight.w500)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: ListenableBuilder(
            listenable: night,
            builder: (context, _) => Row(children: [
              if (night.torchAvailable) ...[
                Expanded(
                  child: _ToolButton(
                    icon: night.torchOn ? Ic.torchOn : Ic.torchOff,
                    label: t.torch,
                    on: night.torchOn,
                    onTap: onTorch,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(child: _ToolButton(icon: Ic.bright, label: t.brighten, on: night.brightOn, onTap: night.toggleBrightness)),
              const SizedBox(width: 8),
              Expanded(child: _ToolButton(icon: Ic.stop, label: t.stop, on: false, danger: true, onTap: onStop)),
            ]),
          ),
        ),
        SectionTitle(t.allSteps),
        ...maneuverTiles(rc.maneuvers, currentIndex: rc.nextIndex, destName: rc.destination?.name, lang: rc.lang),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoLine(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: AppColors.leafDeep),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ]);
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool on;
  final bool danger;
  final VoidCallback onTap;
  const _ToolButton({required this.icon, required this.label, required this.on, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final fg = on ? AppColors.onLamp : (danger ? AppColors.danger : p.text);
    final bg = on ? AppColors.lamp : (danger ? AppColors.danger.withValues(alpha: 0.12) : p.fill);
    return Pressable(
      onTap: onTap,
      radius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          Icon(icon, size: 22, color: fg),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
        ]),
      ),
    );
  }
}

// ── 계산 중 / 도착 ────────────────────────────────────────
class PlanningSheet extends StatelessWidget {
  final ScrollController scroll;
  const PlanningSheet({super.key, required this.scroll});
  @override
  Widget build(BuildContext context) => ListView(controller: scroll, padding: EdgeInsets.zero, children: const [
        Grabber(),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Row(children: [
            LampSpinner(size: 24),
            SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('가장 밝은 길을 찾는 중…', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                SizedBox(height: 2),
                Text('보안등·CCTV·비상벨이 많은 길을 고르고 있어요',
                    style: TextStyle(fontSize: 12, color: AppColors.textSub, fontWeight: FontWeight.w500)),
              ]),
            ),
          ]),
        ),
      ]);
}

/// 도착: 네이버 지도 도착 카드처럼 걸은 거리·걸음 수·걸린 시간
class ArrivedSheet extends StatelessWidget {
  final ScrollController scroll;
  final RouteController rc;
  final VoidCallback onClose;
  const ArrivedSheet({super.key, required this.scroll, required this.rc, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final dist = rc.activeRoute?.distanceM ?? 0;
    final steps = (dist / 0.7).round();
    final start = rc.navStartedAt, end = rc.arrivedAt;
    final mins = start == null || end == null ? null : end.difference(start).inMinutes.clamp(1, 999);
    final t = GuideText.of(rc.lang);
    return ListView(controller: scroll, padding: EdgeInsets.zero, children: [
      const Grabber(),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
        child: Row(children: [
          const IconBadge(Ic.flag, AppColors.leafDeep, size: 46),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.arrivedTitle, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              Text(rc.destination?.name ?? t.arrivedFallback,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSub, fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Row(children: [
          _ArriveStat(Ic.path, fmtDist(dist), t.walked),
          const SizedBox(width: 8),
          _ArriveStat(Ic.footprints, _comma(steps), t.steps),
          const SizedBox(width: 8),
          _ArriveStat(Ic.timer, mins == null ? '-' : t.minutes(mins), t.took),
        ]),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 20), child: AppButton(t.close, onTap: onClose)),
    ]);
  }
}

class _ArriveStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _ArriveStat(this.icon, this.value, this.label);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: Pal.of(context).fill, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Icon(icon, size: 20, color: AppColors.leafDeep),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textSub, fontWeight: FontWeight.w500)),
          ]),
        ),
      );
}
