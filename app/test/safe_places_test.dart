import 'package:ansimdidi/services/safe_places.dart';
import 'package:flutter_test/flutter_test.dart';

/// 카카오 실제 응답(서면 근처, 2026-11)의 카테고리 값으로 확인
void main() {
  group('응급실', () {
    test('병원 응급실만 받는다', () {
      expect(acceptsCategory(SafePlaceKind.emergency, '', '의료,건강 > 병원 > 응급실'), isTrue);
    });
    test('응급실국물떡볶이(음식점)는 제외', () {
      expect(acceptsCategory(SafePlaceKind.emergency, 'FD6', '음식점 > 분식 > 떡볶이 > 응급실국물떡볶이'), isFalse);
    });
    test('응급실이 아닌 일반 병원은 제외', () {
      expect(acceptsCategory(SafePlaceKind.emergency, 'HP8', '의료,건강 > 병원 > 내과'), isFalse);
    });
  });

  group('지구대·파출소', () {
    test('지구대·파출소는 받는다', () {
      expect(acceptsCategory(SafePlaceKind.police, 'PO3', '사회,공공기관 > 행정기관 > 경찰서 > 지구대'), isTrue);
      expect(acceptsCategory(SafePlaceKind.police, 'PO3', '사회,공공기관 > 행정기관 > 경찰서 > 파출소'), isTrue);
    });
    test('방범초소(자율방범대)는 제외', () {
      expect(acceptsCategory(SafePlaceKind.police, '', '사회,공공기관 > 행정기관 > 경찰서 > 파출소 > 방범초소'), isFalse);
    });
    test('이름만 비슷한 가게는 제외', () {
      expect(acceptsCategory(SafePlaceKind.police, 'FD6', '음식점 > 술집 > 호프,요리주점'), isFalse);
    });
  });

  group('편의점·약국', () {
    test('편의점', () {
      expect(acceptsCategory(SafePlaceKind.store, 'CS2', '가정,생활 > 편의점 > CU'), isTrue);
      expect(acceptsCategory(SafePlaceKind.store, 'FD6', '음식점 > 간식 > 편의점도시락'), isFalse);
    });
    test('약국', () {
      expect(acceptsCategory(SafePlaceKind.pharmacy, 'PM9', '의료,건강 > 약국'), isTrue);
      expect(acceptsCategory(SafePlaceKind.pharmacy, 'CE7', '음식점 > 카페 > 약국카페'), isFalse);
    });
  });
}
