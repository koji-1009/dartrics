import 'package:dartrics/src/metrics/class/wmc.dart';
import 'package:test/test.dart';

import 'class_helpers.dart';

void main() {
  const m = WeightedMethodsPerClass();

  test('sum of cyclomatic complexity across methods', () {
    final input = inputFor('''
class C {
  int a() { return 1; }                     // CC = 1
  int b(int x) { if (x > 0) return 1; return 0; }  // CC = 2
  int c(int x, int y) {                     // CC = 4 (3 ifs)
    if (x > 0) {
      if (y > 0) return 1;
    }
    if (x < 0) return -1;
    return 0;
  }
}
''', className: 'C');
    expect(m.compute(input), 1 + 2 + 4);
  });
}
