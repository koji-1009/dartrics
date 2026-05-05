import 'package:dartrics/src/metrics/function/halstead.dart';
import 'package:test/test.dart';

import '_helpers.dart';

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

  test('difficulty grows with operator variety', () {
    final input = inputFor('''
int f(int x) {
  return x + x * x - x ~/ 2;
}
''', name: 'f');
    expect(const HalsteadDifficulty().compute(input), greaterThan(0));
  });

  test('effort = difficulty · volume', () {
    final input = inputFor('''
int f(int x) {
  return x + x * 3;
}
''', name: 'f');
    final v = const HalsteadVolume().compute(input);
    final d = const HalsteadDifficulty().compute(input);
    final e = const HalsteadEffort().compute(input);
    expect(e, closeTo(v * d, 1e-9));
  });
}
