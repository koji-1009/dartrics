import 'package:dartrics/src/metrics/class/cbo.dart';
import 'package:test/test.dart';

import 'class_helpers.dart';

void main() {
  const m = CouplingBetweenObjects();

  test('counts distinct external types in fields and method signatures', () {
    final input = inputFor('''
class A {
  final B b;
  final List<C> cs;
  A(this.b, this.cs);
  D buildD(E e) { return D(e); }
}
class B {}
class C {}
class D { D(E e); }
class E {}
''', className: 'A');
    // A references: B, C, D, E, List → 5
    expect(m.compute(input), 5);
  });

  test('class with only primitives has CBO = 0 (after stdlib filter)', () {
    final input = inputFor('''
class P {
  void run() {}
}
''', className: 'P');
    expect(m.compute(input), 0);
  });
}
