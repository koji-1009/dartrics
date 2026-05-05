import 'package:dartrics/src/metrics/function/max_nesting_level.dart';
import 'package:test/test.dart';

import '_helpers.dart';

void main() {
  const m = MaxNestingLevel();

  test('flat function has depth 0', () {
    final input = inputFor('int f() => 1;', name: 'f');
    expect(m.compute(input), 0);
  });

  test('single if has depth 1', () {
    final input = inputFor('''
int f(int x) {
  if (x > 0) return 1;
  return 0;
}
''', name: 'f');
    expect(m.compute(input), 1);
  });

  test('three-deep nest reports 3', () {
    final input = inputFor('''
int f(int x) {
  for (var i = 0; i < x; i++) {
    if (i % 2 == 0) {
      while (i > 0) {
        i--;
      }
    }
  }
  return x;
}
''', name: 'f');
    expect(m.compute(input), 3);
  });
}
