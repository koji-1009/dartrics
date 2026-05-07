import 'package:dartrics/src/metrics/function/halstead.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('volume increases monotonically with token vocabulary', () {
    final tiny = inputFor('int f() => 1;', name: 'f');
    final bigger = inputFor('''
int f() {
  var a = 1;
  var b = 2;
  var c = a + b;
  return c * 3 - 4;
}
''', name: 'f');

    final v1 = const HalsteadVolume().compute(tiny);
    final v2 = const HalsteadVolume().compute(bigger);
    expect(v2, greaterThan(v1));
  });

  test('vocabulary <= 1 short-circuits to 0', () {
    // The volume formula has log2(vocabulary), which is 0 at
    // vocabulary=1 and undefined at 0. The metric guards against both
    // by returning 0 directly.
    expect(
      HalsteadCounts(
        uniqueOperators: 0,
        uniqueOperands: 0,
        totalOperators: 0,
        totalOperands: 0,
      ).volume,
      0,
    );
  });

  test('exposes raw n1/n2/N1/N2 counts for embedders', () {
    final input = inputFor('''
int f(int x) {
  return x + x;
}
''', name: 'f');
    final counts = HalsteadCounts.fromBody(input.body);
    expect(counts.uniqueOperators, greaterThan(0));
    expect(counts.uniqueOperands, greaterThan(0));
    expect(counts.length, greaterThan(0));
    expect(counts.vocabulary, greaterThan(1));
  });
}
