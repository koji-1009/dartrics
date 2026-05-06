import 'package:dartrics/src/metrics/function/number_of_parameters.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const m = NumberOfParameters();

  test('counts positional and named params', () {
    final input = inputFor('''
int f(int a, int b, {int? c, required int d}) => a;
''', name: 'f');
    expect(m.compute(input), 4);
  });

  test('zero-arg function reports 0', () {
    final input = inputFor('int f() => 1;', name: 'f');
    expect(m.compute(input), 0);
  });
}
