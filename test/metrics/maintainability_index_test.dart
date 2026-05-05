import 'package:dartrics/src/metrics/function/maintainability_index.dart';
import 'package:test/test.dart';

import '_helpers.dart';

void main() {
  const mi = MaintainabilityIndex();

  test('clamped to [0, 171]', () {
    final small = inputFor('int f() => 1;', name: 'f');
    final big = inputFor('''
int f(int x) {
  if (x > 0) {
    for (var i = 0; i < x; i++) {
      if (i % 2 == 0) {
        if (i > 10) {
          if (i > 20) return -1;
        }
      }
    }
  }
  return x;
}
''', name: 'f');
    final smallScore = mi.compute(small);
    final bigScore = mi.compute(big);
    expect(smallScore, inInclusiveRange(0, 171));
    expect(bigScore, inInclusiveRange(0, 171));
    expect(
      smallScore,
      greaterThan(bigScore),
      reason: 'simpler function must be more maintainable',
    );
  });
}
