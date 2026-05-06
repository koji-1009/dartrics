import 'package:dartrics/src/metrics/class/rfc.dart';
import 'package:test/test.dart';

import 'class_helpers.dart';

void main() {
  const m = ResponseForClass();

  test('declared methods + invoked external methods', () {
    final input = inputFor('''
class A {
  void foo() { bar(); print('hi'); }
  void bar() { baz(); }
  void baz() {}
}
''', className: 'A');
    // declared: foo, bar, baz → 3
    // invoked: bar, print, baz → 3 (overlap with declared excluded by union)
    // Union: foo, bar, baz, print → 4
    expect(m.compute(input), 4);
  });
}
