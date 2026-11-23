import 'package:ansim_core/ansim_core.dart';
import 'package:flutter/material.dart';

import '../services/kakao_local.dart';
import '../services/safe_places.dart';
import '../theme.dart';
import 'app_icons.dart';
import 'kit.dart';
import 'map_layers.dart';
import 'sheets.dart';
import 'widgets.dart';

/// 카테고리 칩 → 현위치 주변 안전 장소(가까운 순) → 고르면 그곳까지 안심 경로.
Future<void> showNearbySheet(
  BuildContext context, {
  required SafePlacesService service,
  required GeoPoint center,
  required SafePlaceKind kind,
  required void Function(PlaceRef) onGo,
}) {
  final future = service.nearby(center, kind);
  return showAppSheet(
    context,
    builder: (ctx) => FutureBuilder<List<NearbyPlace>>(
      future: future,
      builder: (ctx, snap) {
        final header = Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
          child: Row(children: [
            IconBadge(safeKindIcon(kind), safeKindColor(kind), size: 36),
            const SizedBox(width: 10),
            Expanded(child: Text('가까운 ${kind.label}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            const Pill('반경 2km'),
          ]),
        );
        final List<Widget> body;
        if (snap.connectionState != ConnectionState.done) {
          body = [const Padding(padding: EdgeInsets.all(36), child: Center(child: LampSpinner(size: 28)))];
        } else if (snap.hasError) {
          body = [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text('${snap.error}'.replaceFirst('Exception: ', ''),
                  style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w500)),
            ),
          ];
        } else {
          final list = snap.data ?? const [];
          body = [
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text('반경 2km 안에서 ${kind.label}을(를) 찾지 못했어요. 위급하면 SOS로 112에 바로 연락하세요.',
                    style: const TextStyle(color: AppColors.textSub, height: 1.5)),
              ),
            for (final n in list)
              PlaceLine(
                icon: safeKindIcon(kind),
                color: safeKindColor(kind),
                title: n.place.name,
                subtitle: n.place.address,
                trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(fmtDist(n.distanceM), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.leafDeep)),
                  const Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('안심 경로', style: TextStyle(fontSize: 10.5, color: AppColors.textSub, fontWeight: FontWeight.w500)),
                    Icon(Ic.chevron, size: 11, color: AppColors.textSub),
                  ]),
                ]),
                onTap: () {
                  Navigator.pop(ctx);
                  onGo(PlaceRef(
                    name: n.place.name,
                    address: n.place.address,
                    category: kind.label,
                    point: n.place.point,
                    distanceM: n.distanceM,
                  ));
                },
              ),
            const SizedBox(height: 12),
          ];
        }
        return ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [header, ...body]);
      },
    ),
  );
}
