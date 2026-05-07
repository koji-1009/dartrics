import 'package:dartrics/src/metrics/function/number_of_parameters.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const m = NumberOfParameters();

  test('counts positional params, ignores named', () {
    // `a` and `b` are positional; `c` (optional named) and `d`
    // (required named) carry their names at the call site, so they
    // contribute zero to the lens — same rule as `boolean-trap`.
    final input = inputFor('''
int f(int a, int b, {int? c, required int d}) => a;
''', name: 'f');
    expect(m.compute(input), 2);
  });

  test('all-named signature scores zero regardless of count', () {
    // The whole point of moving to weight-zero on named: a Dart
    // signature with many named knobs reads cleanly at the call site
    // and shouldn't trip the lens. Six named params land at 0.
    final input = inputFor('''
int f({required int a, required int b, int? c, int? d, int? e, int? g}) => a;
''', name: 'f');
    expect(m.compute(input), 0);
  });

  test('counts optional positional params', () {
    // Optional positional (`[int? x]`) still requires the reader to
    // recover meaning by position at the call site, so it counts.
    final input = inputFor('int f(int a, [int? b, int? c]) => a;', name: 'f');
    expect(m.compute(input), 3);
  });

  test('zero-arg function reports 0', () {
    final input = inputFor('int f() => 1;', name: 'f');
    expect(m.compute(input), 0);
  });
}
