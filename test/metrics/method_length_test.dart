import 'package:dartrics/src/metrics/function/method_length.dart';
import 'package:test/test.dart';

import '_helpers.dart';

void main() {
  const m = MethodLength();

  test('single-line expression body counts as 1', () {
    final input = inputFor('int f() => 1;', name: 'f');
    expect(m.compute(input), 1);
  });

  test('multiline body counts every line including blanks/comments', () {
    final input = inputFor('''
int f(int x) {
  // c
  var y = x;

  return y;
}
''', name: 'f');
    // body spans `{` line through `}` line — 6 lines.
    expect(m.compute(input), 6);
  });
}
