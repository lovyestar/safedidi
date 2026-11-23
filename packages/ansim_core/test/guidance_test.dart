import 'dart:typed_data';

import 'package:ansim_core/ansim_core.dart';
import 'package:test/test.dart';

/// 십자 교차로 B에서 북쪽은 '서면로'(횡단보도 포함), 동쪽은 직진,
/// 따로 떨어진 ㄱ자 골목(교차로 아님)과 완만하게 휘는 길.
void main() {
  const lat0 = 35.15, lng0 = 129.05;
  final mLng = metersPerDegLng(lat0);
  GeoPoint p(double north, double east) => GeoPoint(lat0 + north / metersPerDegLat, lng0 + east / mLng);

  final gb = RoadGraphBuilder();
  final minor = RoadFlags.encode(RoadClass.minor);
  int node(double n, double e) => gb.addNode(p(n, e).lat, p(n, e).lng);
  final a = node(0, 0), b = node(0, 100), c1 = node(15, 100), c = node(100, 100), d = node(-100, 100), e = node(0, 200);
  gb.addEdge(a, b, flags: minor, name: '중앙대로');
  gb.addEdge(b, c1, flags: minor, name: '서면로', feature: EdgeFeature.crossing);
  gb.addEdge(c1, c, flags: minor, name: '서면로');
  gb.addEdge(b, d, flags: minor);
  gb.addEdge(b, e, flags: minor, name: '중앙대로');
  // ㄱ자 골목(교차로 아님): F(500,0) → G(500,100) → H(600,100)
  final f = node(500, 0), g = node(500, 100), h = node(600, 100);
  gb.addEdge(f, g, flags: minor);
  gb.addEdge(g, h, flags: minor);
  // 완만하게(약 40°) 휘는 길(교차로 아님): I(-500,0) → J(-500,100) → K(-416,170)
  final i = node(-500, 0), j = node(-500, 100), k = node(-416, 170);
  gb.addEdge(i, j, flags: minor);
  gb.addEdge(j, k, flags: minor);
  final graph = gb.build();

  test('교차로 좌회전 + 횡단보도는 한 안내로 합친다', () {
    final ms = buildManeuvers([p(0, 0), p(0, 100), p(15, 100), p(100, 100)], graph);
    expect(ms.first.turn, TurnKind.depart);
    expect(ms.first.road, '중앙대로');
    expect(ms.last.turn, TurnKind.arrive);
    final mid = ms.sublist(1, ms.length - 1);
    expect(mid, hasLength(1));
    expect(mid.single.turn, TurnKind.left);
    expect(mid.single.feature, EdgeFeature.crossing);
    expect(mid.single.atM, closeTo(100, 1));
    expect(mid.single.road, '서면로');
    expect(mid.single.title, '좌회전 후 횡단보도 건너기');
    expect(mid.single.speech, '왼쪽 방향, 횡단보도를 건너세요');
  });

  test('교차로 직진은 안내하지 않는다', () {
    final ms = buildManeuvers([p(0, 0), p(0, 100), p(0, 200)], graph);
    expect(ms.map((m) => m.turn), [TurnKind.depart, TurnKind.arrive]);
  });

  test('남쪽으로 오다 동쪽으로 꺾으면 좌회전', () {
    final ms = buildManeuvers([p(100, 100), p(15, 100), p(0, 100), p(0, 200)], graph);
    final turns = ms.where((m) => m.turn.isTurn).toList();
    expect(turns, hasLength(1));
    expect(turns.single.turn, TurnKind.left); // 남쪽으로 내려오다 동쪽 = 왼쪽
  });

  test('교차로가 아니어도 90° 모퉁이는 안내', () {
    final ms = buildManeuvers([p(500, 0), p(500, 100), p(600, 100)], graph);
    expect(ms.where((m) => m.turn.isTurn).single.turn, TurnKind.left);
  });

  test('교차로 아닌 완만한 굽이는 안내하지 않는다', () {
    final ms = buildManeuvers([p(-500, 0), p(-500, 100), p(-416, 170)], graph);
    expect(ms.where((m) => m.turn.isTurn), isEmpty);
  });

  test('도착 연결선으로 꺾는 대신 "목적지는 왼쪽"으로 안내', () {
    // 중앙대로를 동쪽으로 200m(B에서 직진) 간 뒤 도로를 벗어나 북쪽 30m의 목적지로(연결선)
    final route = [p(0, 0), p(0, 100), p(0, 200), p(30, 200)];
    final ms = buildManeuvers(route, graph, roadEndM: 200);
    expect(ms.where((m) => m.turn.isTurn), isEmpty); // 연결선으로 꺾는 '좌회전'은 없다
    final arrive = ms.last;
    expect(arrive.turn, TurnKind.arrive);
    expect(arrive.atM, closeTo(200, 1)); // 도로를 벗어나는 곳에서 안내
    expect(arrive.side, -1);
    expect(arrive.title, '목적지는 왼쪽');
    expect(arrive.speech, '목적지는 왼쪽에 있습니다');

    // 남쪽(오른쪽)에 있으면 오른쪽, 연결선을 모르면 예전처럼 방향 없이 끝점에서 도착
    final right = buildManeuvers([p(0, 0), p(0, 100), p(0, 200), p(-30, 200)], graph, roadEndM: 200);
    expect(right.last.sideText, '오른쪽');
    final plain = buildManeuvers([p(0, 0), p(0, 100), p(0, 200)], graph);
    expect(plain.last.side, 0);
    expect(plain.last.title, '목적지 도착');
  });

  test('영어·일본어 안내 문장', () {
    final m = buildManeuvers([p(0, 0), p(0, 100), p(15, 100), p(100, 100)], graph)[1]; // 좌회전 + 횡단보도
    const en = GuidePhrases.en, ja = GuidePhrases.ja, ko = GuidePhrases.ko;
    expect(ko.title(m), '좌회전 후 횡단보도 건너기');
    expect(en.title(m), 'Turn left, then cross the crosswalk');
    expect(en.speech(m), 'Turn left, then cross the crosswalk');
    expect(en.soon(en.speech(m), 43), 'In 40 meters, turn left, then cross the crosswalk');
    expect(ja.title(m), '左折して横断歩道を渡る');
    expect(ja.speech(m), '左方向、横断歩道を渡ってください');
    expect(ja.soon(ja.turnSpeech(TurnKind.left), 47), '50メートル先、左方向です');
    expect(en.road('서면로'), 'Seomyeon-ro');
    expect(ja.spokenRoad('서면로'), isNull); // 일본어 음성은 로마자 도로 이름을 읽지 않는다

    final arrive = buildManeuvers([p(0, 0), p(0, 100), p(0, 200), p(30, 200)], graph, roadEndM: 200).last;
    expect(en.title(arrive), 'Destination on the left');
    expect(en.speech(arrive), 'Your destination is on the left');
    expect(ja.title(arrive), '目的地は左側');
    expect(ja.arrived(-1), '目的地に到着しました。目的地は左側です。');
    expect(en.arrived(1), 'You have arrived. Your destination is on the right.');
    expect(ko.arrived(-1), '목적지에 도착했어요. 목적지는 왼쪽에 있어요.');

    expect(
      en.start(kind: RouteKind.safe, minutes: 10, distanceM: 703, score: 44, first: m, firstDistM: 536, firstRoad: '중앙대로'),
      'Starting safe route guidance. About 10 minutes, 703 meters, safety score 44. Go straight for 536 meters on Jungang-daero.',
    );
    expect(
      ja.start(kind: RouteKind.safe, minutes: 10, distanceM: 703, score: 44, first: m, firstDistM: 536, firstRoad: '중앙대로'),
      '安心ルートの案内を開始します。約10分、703メートル、安心指数は44点です。536メートル直進してください。',
    );
    expect(GuideLang.parse('ja'), GuideLang.ja);
    expect(GuideLang.parse('xx'), GuideLang.ko);
  });

  test('도로 이름 로마자 표기', () {
    expect(romanizeRoad('중앙대로'), 'Jungang-daero');
    expect(romanizeRoad('중앙대로783번길'), 'Jungang-daero 783beon-gil');
    expect(romanizeRoad('우동1로20번길'), 'Udong 1-ro 20beon-gil');
    expect(romanizeRoad('전포대로199번길'), 'Jeonpo-daero 199beon-gil');
    expect(romanizeRoad('서전로'), 'Seojeon-ro');
    expect(romanizeRoad('중동길1번길'), 'Jungdong-gil 1beon-gil');
    expect(romanizeRoad('태종로'), 'Taejong-ro');
    expect(romanizeRoad('동천로'), 'Dongcheon-ro');
  });

  test('각도 분류', () {
    expect(TurnKind.fromAngle(10), TurnKind.straight);
    expect(TurnKind.fromAngle(45), TurnKind.slightRight);
    expect(TurnKind.fromAngle(-90), TurnKind.left);
    expect(TurnKind.fromAngle(135), TurnKind.sharpRight);
    expect(TurnKind.fromAngle(170), TurnKind.uTurn);
  });

  test('다음 안내 찾기', () {
    final ms = buildManeuvers([p(0, 0), p(0, 100), p(15, 100), p(100, 100)], graph);
    final cur = GuidanceCursor(ms);
    expect(ms[cur.nextIndex(10)].turn, TurnKind.left);
    expect(ms[cur.nextIndex(150)].turn, TurnKind.arrive);
  });

  test('graph.bin v2: 도로 이름·특징 왕복', () {
    final back = RoadGraph.fromBytes(ByteData.sublistView(graph.toBytes()));
    expect(back.names, graph.names);
    expect(back.edgeFeature, graph.edgeFeature);
    expect(back.edgeName, graph.edgeName);
    final e = List.generate(back.edgeCount, (x) => x).firstWhere((x) => back.featureOf(x) == EdgeFeature.crossing);
    expect(back.nameOf(e), '서면로');
  });
}
