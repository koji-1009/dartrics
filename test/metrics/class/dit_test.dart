import 'package:dartrics/src/metrics/class/dit.dart';
import 'package:test/test.dart';

import 'class_helpers.dart';

void main() {
  const m = DepthOfInheritanceTree();

  test('class with no extends has DIT = 1 (one step from Object)', () {
    final input = inputFor('class A {}', className: 'A');
    expect(m.compute(input), 1);
  });

  test('explicit extends Object has DIT = 1', () {
    final input = inputFor('class A extends Object {}', className: 'A');
    expect(m.compute(input), 1);
  });

  test('three-level chain reports DIT = 3', () {
    final input = inputFor('''
class A {}
class B extends A {}
class C extends B {}
''', className: 'C');
    expect(m.compute(input), 3);
  });

  test('external superclass collapses to 2', () {
    final input = inputFor('class W extends Widget {}', className: 'W');
    expect(m.compute(input), 2);
  });
}
