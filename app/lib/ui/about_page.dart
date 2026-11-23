import 'package:ansim_core/ansim_core.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../data/safety_data.dart';
import '../theme.dart';
import 'app_icons.dart';
import 'kit.dart';
import 'widgets.dart';

/// 데이터 출처·라이선스·안심지수 계산 방식·키 설정 상태.
class AboutPage extends StatelessWidget {
  final SafetyData data;
  const AboutPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final f = data.facilities;
    final sources = ((data.meta['sources'] as List?) ?? const []).cast<Map>();
    final g = (data.meta['graph'] as Map?) ?? const {};
    final filtered = (data.meta['filtered'] as Map?)?['carOnlyLights'];
    String comma(int v) => v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    Widget para(String s) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(s, style: const TextStyle(fontSize: 13, height: 1.6, fontWeight: FontWeight.w500)),
        );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          const PageHeader(title: '안심디디 정보'),
          const SizedBox(height: 6),
          GroupCard(title: '안심지수는 이렇게 계산해요', children: [
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                para('경로를 10m 간격으로 나눠 각 지점 주변의 안전시설을 셉니다.'),
                const _Weight(icon: Ic.light, color: AppColors.lampDeep, label: '조명', pct: 55, what: '반경 30m 보안등 밀집도 · 대로는 도로 등급으로 가로등 보정'),
                const _Weight(icon: Ic.cctv, color: AppColors.cctv, label: 'CCTV', pct: 35, what: '반경 50m 방범용 CCTV 밀집도'),
                const _Weight(icon: Ic.bell, color: AppColors.bell, label: '비상벨', pct: 10, what: '반경 60m 안전비상벨'),
                const SizedBox(height: 6),
                para('안심 경로는 이 점수를 도로 비용에 반영한 A* 탐색으로, 최단 거리의 1.5배(+200m) 안에서 가장 밝은 길을 고릅니다. '
                    '모든 계산은 서버 없이 이 기기 안에서 이뤄져요.'),
              ]),
            ),
          ]),
          GroupCard(title: '내장 데이터 (부산광역시)', children: [
            GroupRow(
              icon: Ic.light,
              color: AppColors.lampDeep,
              title: '보안등 ${comma(f.countOf(FacilityType.light))}개',
              subtitle: filtered == null ? null : '고속도로·자동차전용도로 위 $filtered곳은 걷는 길을 비추지 않아 뺐어요',
            ),
            GroupRow(icon: Ic.cctv, color: AppColors.cctv, title: 'CCTV ${comma(f.countOf(FacilityType.cctv))}대'),
            GroupRow(icon: Ic.bell, color: AppColors.bell, title: '비상벨 ${comma(f.countOf(FacilityType.bell))}개'),
            GroupRow(
              icon: Ic.path,
              color: AppColors.leafDeep,
              title: '보행 도로망 ${g['roadKm'] ?? '?'}km',
              subtitle: '노드 ${comma(data.graph.nodeCount)}개 · 도로 이름 ${comma(data.graph.names.length - 1)}개'
                  '${data.osmTimestamp.isNotEmpty ? ' · OSM 기준 ${data.osmTimestamp.substring(0, 10)}' : ''}',
            ),
          ]),
          GroupCard(title: '출처·라이선스', children: [
            for (final s in sources)
              GroupRow(icon: Ic.data, color: AppColors.textSub, title: '${s['name']}', subtitle: '${s['provider']} · ${s['license']}'),
            const GroupRow(
              icon: Ic.explore,
              color: AppColors.textSub,
              title: '지도 타일 © OpenStreetMap contributors',
              subtitle: 'ODbL · 글꼴 Pretendard (SIL OFL 1.1) · 아이콘 Phosphor (MIT)',
            ),
          ]),
          GroupCard(title: '꼭 알아두세요', children: [
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: para('안심지수는 공공 안전시설의 위치를 바탕으로 한 참고 지표이며 실제 안전을 보장하지 않습니다. '
                  '공공데이터의 보안등은 골목 위주라 큰길의 도로 가로등은 개수에 들어가지 않아요(점수는 도로 등급으로 보정). '
                  'CCTV는 설치 위치 정보이며 실시간 작동 여부를 뜻하지 않습니다. 위급할 때는 바로 112에 신고하세요.'),
            ),
          ]),
          GroupCard(title: 'API 키 설정 상태', children: [
            _KeyRow(name: '카카오 로컬', ok: AppConfig.hasKakao, what: '장소 검색·주소 확인'),
            _KeyRow(name: 'TMAP', ok: AppConfig.hasTmap, what: '최단 보행 경로 — 없으면 앱 내장 최단 경로'),
          ]),
        ]),
      ),
    );
  }
}

class _Weight extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int pct;
  final String what;
  const _Weight({required this.icon, required this.color, required this.label, required this.pct, required this.what});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(children: [
          IconBadge(icon, color, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('$pct%', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
              ]),
              const SizedBox(height: 4),
              ProgressLine(value: pct / 100, height: 5, color: color),
              const SizedBox(height: 3),
              Text(what, style: const TextStyle(fontSize: 11.5, color: AppColors.textSub, fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
      );
}

class _KeyRow extends StatelessWidget {
  final String name;
  final bool ok;
  final String what;
  const _KeyRow({required this.name, required this.ok, required this.what});

  @override
  Widget build(BuildContext context) => GroupRow(
        icon: ok ? Ic.ok : Ic.warning,
        color: ok ? AppColors.leafDeep : AppColors.plain,
        title: name,
        subtitle: what,
        trailing: Pill(ok ? '설정됨' : '없음', color: ok ? AppColors.leafDeep : AppColors.textSub),
      );
}
