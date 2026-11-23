import 'dart:async';

import 'package:ansim_core/ansim_core.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../services/kakao_local.dart';
import '../services/prefs.dart';
import '../theme.dart';
import 'app_icons.dart';
import 'kit.dart';
import 'widgets.dart';

/// 장소 검색(카카오 로컬, 부산 범위). 검색어가 없으면 집·회사·최근 검색을 보여준다.
/// 출발지 검색이면 맨 위에 '현위치' 항목.
class SearchPage extends StatefulWidget {
  final KakaoLocalService kakao;
  final AppPrefs prefs;
  final bool forOrigin;
  final String? title;
  final GeoPoint? near;
  final String? currentLocationLabel;

  const SearchPage({
    super.key,
    required this.kakao,
    required this.prefs,
    required this.forOrigin,
    this.title,
    this.near,
    this.currentLocationLabel,
  });

  /// 현위치 선택을 나타내는 특별 값.
  static const currentLocation = PlaceRef(name: '현위치', point: GeoPoint(0, 0), isCurrentLocation: true);

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<PlaceRef> _results = const [];
  bool _loading = false;
  String? _error;
  int _seq = 0;

  static const _examples = ['서면역', '부산대학교', '해운대해수욕장', '부산시청'];

  AppPrefs get prefs => widget.prefs;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  void _fill(String q) {
    _ctrl.value = TextEditingValue(text: q, selection: TextSelection.collapsed(offset: q.length));
    _debounce?.cancel();
    setState(() {});
    _search(q);
  }

  Future<void> _search(String q) async {
    final seq = ++_seq;
    if (q.trim().isEmpty) {
      setState(() {
        _results = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final r = await widget.kakao.search(q, near: widget.near);
      if (seq != _seq || !mounted) return;
      setState(() {
        _results = r;
        _error = r.isEmpty ? '부산 안에서 "${q.trim()}" 검색 결과가 없어요' : null;
      });
    } catch (e) {
      if (seq != _seq || !mounted) return;
      setState(() {
        _results = const [];
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (seq == _seq && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveAs(PlaceRef p, {required bool home}) async {
    home ? await prefs.setHome(p) : await prefs.setWork(p);
    if (mounted) showToast(context, '${p.name}을(를) ${home ? '집' : '회사'}으로 저장했어요');
  }

  /// ⋯ 버튼: 집·회사로 저장, 최근 검색에서 지우기
  Future<void> _placeMenu(PlaceRef p, {bool recent = false}) async {
    final v = await showAppSheet<String>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
            child: Text(p.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          if (p.address != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(p.address!, style: const TextStyle(fontSize: 12.5, color: AppColors.textSub)),
            ),
          GroupRow(icon: Ic.home, color: AppColors.leafDeep, title: '집으로 저장', onTap: () => Navigator.pop(ctx, 'home')),
          GroupRow(icon: Ic.work, color: AppColors.leafDeep, title: '회사로 저장', onTap: () => Navigator.pop(ctx, 'work')),
          if (recent)
            GroupRow(
              icon: Ic.trash,
              color: AppColors.danger,
              title: '최근 검색에서 지우기',
              titleColor: AppColors.danger,
              onTap: () => Navigator.pop(ctx, 'del'),
            ),
        ]),
      ),
    );
    switch (v) {
      case 'home':
        await _saveAs(p, home: true);
      case 'work':
        await _saveAs(p, home: false);
      case 'del':
        await prefs.removeRecent(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final q = _ctrl.text.trim();
    return Scaffold(
      backgroundColor: p.surface,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 16, 8),
            child: Row(children: [
              CircleBtn.plain(icon: Ic.back, label: '뒤로', onTap: () => Navigator.pop(context)),
              const SizedBox(width: 4),
              Expanded(
                child: AppTextField(
                  controller: _ctrl,
                  hint: widget.title ?? (widget.forOrigin ? '출발지를 검색하세요' : '어디로 갈까요?'),
                  icon: Ic.search,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  onSubmitted: _search,
                ),
              ),
            ]),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: prefs,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.only(bottom: 24),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: q.isEmpty ? _idle() : _resultList(q),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // 검색어가 없을 때: 현위치 · 집/회사 · 최근 검색(없으면 예시)
  List<Widget> _idle() => [
        if (!AppConfig.hasKakao)
          const _Notice(
            text: '카카오 REST API 키가 없어 장소 검색을 할 수 없어요.\nkeys.json에 KAKAO_REST_API_KEY를 넣고 다시 빌드해 주세요.',
          ),
        if (widget.forOrigin)
          _PlaceRow(
            icon: Ic.myLocation,
            color: AppColors.leafDeep,
            name: '현위치에서 출발',
            strong: true,
            sub: widget.currentLocationLabel ?? 'GPS 위치 사용',
            onTap: () => Navigator.pop(context, SearchPage.currentLocation),
          ),
        if (prefs.home != null || prefs.work != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(children: [
              if (prefs.home != null)
                Expanded(
                  child: _QuickFav(
                    icon: Ic.home,
                    label: '집',
                    name: prefs.home!.name,
                    onTap: () => Navigator.pop(context, prefs.home),
                  ),
                ),
              if (prefs.home != null && prefs.work != null) const SizedBox(width: 10),
              if (prefs.work != null)
                Expanded(
                  child: _QuickFav(
                    icon: Ic.work,
                    label: '회사',
                    name: prefs.work!.name,
                    onTap: () => Navigator.pop(context, prefs.work),
                  ),
                ),
            ]),
          ),
        if (prefs.recent.isNotEmpty) ...[
          SectionTitle('최근 검색', trailing: TextLink('전체 삭제', onTap: prefs.clearRecent)),
          for (final p in prefs.recent)
            _PlaceRow(
              icon: Ic.recent,
              color: AppColors.textSub,
              name: p.name,
              sub: p.address,
              onTap: () => Navigator.pop(context, p),
              onMore: () => _placeMenu(p, recent: true),
            ),
        ] else if (AppConfig.hasKakao)
          _EmptyHint(examples: _examples, onPick: _fill),
      ];

  List<Widget> _resultList(String q) => [
        if (_loading && _results.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(children: [
              LampSpinner(size: 18, stroke: 2.5),
              SizedBox(width: 10),
              Text('찾는 중…', style: TextStyle(fontSize: 12.5, color: AppColors.textSub, fontWeight: FontWeight.w500)),
            ]),
          ),
        if (_error != null && !_loading) _EmptyState(text: _error!),
        if (_results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: Text('장소 ${_results.length}곳',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSub)),
          ),
        for (final p in _results)
          _PlaceRow(
            icon: _categoryIcon(p.category),
            color: AppColors.leafDeep,
            name: p.name,
            query: q,
            sub: [if (p.category != null) p.category!, if (p.address != null) p.address!].join(' · '),
            distance: p.distanceM == null ? null : fmtDist(p.distanceM!),
            onTap: () => Navigator.pop(context, p),
            onMore: () => _placeMenu(p),
          ),
      ];
}

/// 카카오 분류명으로 고른 아이콘
IconData _categoryIcon(String? c) {
  final s = c ?? '';
  if (s.contains('지하철')) return Ic.subway;
  if (s.contains('학교') || s.contains('학원')) return Ic.school;
  if (s.contains('카페')) return Ic.cafe;
  if (s.contains('음식')) return Ic.food;
  if (s.contains('병원')) return Ic.hospital;
  if (s.contains('약국')) return Ic.pharmacy;
  if (s.contains('편의점')) return Ic.store;
  if (s.contains('마트') || s.contains('쇼핑')) return Ic.shopping;
  if (s.contains('공공') || s.contains('관공')) return Ic.publicOffice;
  if (s.contains('관광') || s.contains('문화') || s.contains('공원')) return Ic.park;
  if (s.contains('숙박')) return Ic.hotel;
  if (s.contains('주차')) return Ic.parking;
  return Ic.place;
}

/// 장소 한 줄: 아이콘 배지 · 이름(검색어 강조) · 분류·주소 · 거리 · ⋯
class _PlaceRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String name;
  final String? query;
  final String? sub;
  final String? distance;
  final bool strong;
  final VoidCallback onTap;
  final VoidCallback? onMore;

  const _PlaceRow({
    required this.icon,
    required this.color,
    required this.name,
    required this.onTap,
    this.query,
    this.sub,
    this.distance,
    this.strong = false,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: 14.5,
      fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
      color: Pal.of(context).text,
      fontFamily: 'Pretendard',
    );
    return Pressable(
      onTap: onTap,
      onLongPress: onMore,
      scale: 0.985,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10, onMore == null ? 16 : 6, 10),
        child: Row(children: [
          IconBadge(icon, color, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(_highlight(name, query, base), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (sub != null && sub!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(sub!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSub, fontWeight: FontWeight.w500)),
              ],
            ]),
          ),
          if (distance != null) ...[const SizedBox(width: 8), Pill(distance!)],
          if (onMore != null) CircleBtn.plain(icon: Ic.more, label: '더보기', size: 40, fg: AppColors.textSub, onTap: onMore),
        ]),
      ),
    );
  }

  /// 이름 속 검색어를 초록 글씨로(지도 앱처럼)
  static TextSpan _highlight(String text, String? q, TextStyle base) {
    final query = q?.trim() ?? '';
    if (query.isEmpty) return TextSpan(text: text, style: base);
    final lower = text.toLowerCase(), ql = query.toLowerCase();
    final spans = <TextSpan>[];
    var i = 0;
    while (true) {
      final j = lower.indexOf(ql, i);
      if (j < 0) break;
      if (j > i) spans.add(TextSpan(text: text.substring(i, j)));
      spans.add(TextSpan(
        text: text.substring(j, j + query.length),
        style: const TextStyle(color: AppColors.leafDeep, fontWeight: FontWeight.w700),
      ));
      i = j + query.length;
    }
    if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
    return TextSpan(style: base, children: spans);
  }
}

class _QuickFav extends StatelessWidget {
  final IconData icon;
  final String label;
  final String name;
  final VoidCallback onTap;
  const _QuickFav({required this.icon, required this.label, required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        radius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(color: Pal.of(context).fill, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            IconBadge(icon, AppColors.leafDeep, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textSub, fontWeight: FontWeight.w500)),
              ]),
            ),
          ]),
        ),
      );
}

/// 최근 검색이 없을 때: 안내 + 눌러서 바로 찾는 예시
class _EmptyHint extends StatelessWidget {
  final List<String> examples;
  final ValueChanged<String> onPick;
  const _EmptyHint({required this.examples, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 0),
      child: Column(children: [
        const IconBadge(Ic.explore, AppColors.leafDeep, size: 60),
        const SizedBox(height: 16),
        const Text('장소명·주소·역 이름으로 찾아보세요', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('부산 안의 장소만 검색돼요', style: TextStyle(fontSize: 12.5, color: AppColors.textSub)),
        const SizedBox(height: 20),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          for (final e in examples)
            Pressable(
              onTap: () => onPick(e),
              scale: 0.95,
              radius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(color: p.fill, borderRadius: BorderRadius.circular(20)),
                child: Text(e, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ),
        ]),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;
  const _EmptyState({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 56, 24, 0),
        child: Column(children: [
          const Icon(Ic.noResult, size: 44, color: AppColors.textSub),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.textSub, height: 1.5)),
        ]),
      );
}

class _Notice extends StatelessWidget {
  final String text;
  const _Notice({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Ic.key, size: 20, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w500, height: 1.45)),
          ),
        ]),
      );
}
