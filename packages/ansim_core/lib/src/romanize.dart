/// 한글 도로 이름 → 로마자(국어의 로마자 표기법 기본 규칙, 도로명 표기 방식).
///
/// 예: 중앙대로 → Jungang-daero, 중앙대로783번길 → Jungang-daero 783beon-gil,
///     우동1로20번길 → Udong 1-ro 20beon-gil
/// 영어·일본어 안내에서 도로 이름을 읽을 수 있게 쓴다. 자음 동화 같은 발음 규칙은 다루지 않는다.
String romanizeRoad(String name) {
  final tokens = RegExp(r'[가-힣]+|\d+|[^가-힣\d]+').allMatches(name).map((m) => m.group(0)!).toList();
  final out = StringBuffer();
  String? prev; // 직전 토큰 종류: 'h'(한글) 'd'(숫자) 'o'(기타)
  for (final t in tokens) {
    if (RegExp(r'^\d+$').hasMatch(t)) {
      if (prev == 'h') out.write(' ');
      out.write(t);
      prev = 'd';
      continue;
    }
    if (!RegExp(r'^[가-힣]+$').hasMatch(t)) {
      out.write(t);
      prev = 'o';
      continue;
    }
    // 숫자 바로 뒤: 1로 → 1-ro, 20번길 → 20beon-gil, 3길 → 3-gil
    if (prev == 'd') {
      if (t == '번길') {
        out.write('beon-gil');
      } else if (t == '로' || t == '길' || t == '대로') {
        out.write('-${romanizeHangul(t)}');
      } else {
        out.write(' ${_cap(romanizeHangul(t))}');
      }
      prev = 'h';
      continue;
    }
    if (prev != null && prev != 'o') out.write(' ');
    out.write(_word(t));
    prev = 'h';
  }
  return out.toString().trim();
}

/// 이름 + 길 종류(대로·로·길)를 붙임표로 나눈다: 전포대로 → Jeonpo-daero
String _word(String t) {
  for (final suffix in const ['대로', '번길', '로', '길']) {
    if (t.length > suffix.length && t.endsWith(suffix)) {
      final base = t.substring(0, t.length - suffix.length);
      return '${_cap(romanizeHangul(base))}-${romanizeHangul(suffix)}';
    }
  }
  return _cap(romanizeHangul(t));
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

const _initials = ['g', 'kk', 'n', 'd', 'tt', 'r', 'm', 'b', 'pp', 's', 'ss', '', 'j', 'jj', 'ch', 'k', 't', 'p', 'h'];
const _medials = [
  'a', 'ae', 'ya', 'yae', 'eo', 'e', 'yeo', 'ye', 'o', 'wa', 'wae', 'oe', 'yo', 'u', 'wo', 'we', 'wi', 'yu', 'eu', 'ui', 'i',
];
// 받침(끝소리)
const _finals = [
  '', 'k', 'k', 'k', 'n', 'n', 'n', 't', 'l', 'k', 'm', 'l', 'l', 'l', 'p', 'l', 'm', 'p', 'p', 't', 't', 'ng', 't', 't',
  'k', 't', 'p', 't',
];
// 받침 뒤에 모음(ㅇ)이 오면 다음 글자의 첫소리로 넘어가 읽힌다(연음): 받침 → 첫소리 표기
const _linked = [
  '', 'g', 'kk', 'gs', 'n', 'nj', 'nh', 'd', 'r', 'lg', 'lm', 'lb', 'ls', 'lt', 'lp', 'lh', 'm', 'b', 'bs', 's', 'ss', 'ng',
  'j', 'ch', 'k', 't', 'p', 'h',
];

/// 한글 음절 → 로마자(소문자). 한글이 아닌 글자는 그대로 둔다.
String romanizeHangul(String s) {
  final out = StringBuffer();
  final codes = s.runes.toList();
  for (var i = 0; i < codes.length; i++) {
    final c = codes[i];
    if (c < 0xAC00 || c > 0xD7A3) {
      out.writeCharCode(c);
      continue;
    }
    final idx = c - 0xAC00;
    final ini = idx ~/ 588, med = (idx % 588) ~/ 28, fin = idx % 28;
    // 앞 글자 받침 ㄹ + 이 글자 첫소리 ㄹ → ll
    final prevFinL = i > 0 && codes[i - 1] >= 0xAC00 && codes[i - 1] <= 0xD7A3 && (codes[i - 1] - 0xAC00) % 28 == 8;
    out.write(ini == 5 && prevFinL ? 'l' : _initials[ini]);
    out.write(_medials[med]);
    if (fin == 0) continue;
    final next = i + 1 < codes.length ? codes[i + 1] : -1;
    final nextVowelStart = next >= 0xAC00 && next <= 0xD7A3 && (next - 0xAC00) ~/ 588 == 11;
    out.write(nextVowelStart && fin != 21 ? _linked[fin] : _finals[fin]);
  }
  return out.toString();
}
