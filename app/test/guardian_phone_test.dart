import 'package:ansimdidi/ui/guardian_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('휴대폰 번호 하이픈', () {
    expect(formatPhone('010'), '010');
    expect(formatPhone('0101'), '010-1');
    expect(formatPhone('0101234'), '010-123-4');
    expect(formatPhone('01012345678'), '010-1234-5678');
    expect(formatPhone('010-1234-5678'), '010-1234-5678');
    expect(formatPhone('010123456789'), '010-1234-5678'); // 넘치는 숫자는 버림
  });

  test('지역 번호', () {
    expect(formatPhone('021234567'), '02-123-4567');
    expect(formatPhone('0212345678'), '02-1234-5678');
    expect(formatPhone('0511234567'), '051-123-4567');
    expect(formatPhone('05112345678'), '051-1234-5678');
  });

  test('번호 확인', () {
    expect(isValidPhone('010-1234-5678'), isTrue);
    expect(isValidPhone('02-123-4567'), isTrue);
    expect(isValidPhone('1234'), isFalse);
    expect(isValidPhone('112'), isFalse);
  });
}
