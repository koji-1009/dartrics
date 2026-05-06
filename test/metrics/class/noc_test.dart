import 'package:dartrics/src/metrics/class/noc.dart';
import 'package:test/test.dart';

import 'class_helpers.dart';

void main() {
  const m = NumberOfChildren();

  test('class with no subclasses returns 0', () {
    final input = inputFor('class A {}', className: 'A');
    expect(m.compute(input), 0);
  });

  test('counts only direct subclasses', () {
    final input = inputFor('''
class A {}
class B extends A {}
class C extends A {}
class D extends B {}
''', className: 'A');
    expect(m.compute(input), 2);
  });
}
