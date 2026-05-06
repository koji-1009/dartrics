import 'package:dartrics/src/metrics/function/boolean_trap.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const m = BooleanTrap();

  test('counts every bool-typed positional parameter', () {
    final input = inputFor('''
void f(bool a, bool b, int c) {}
''', name: 'f');
    expect(m.compute(input), 2);
  });

  test('counts bool-typed named parameters too', () {
    final input = inputFor('''
void f({bool? a, required bool b, int? c}) {}
''', name: 'f');
    expect(m.compute(input), 2);
  });

  test('zero on non-bool parameters', () {
    final input = inputFor('int f(int a, String b) => a;', name: 'f');
    expect(m.compute(input), 0);
  });

  test('zero on a parameter-less function', () {
    final input = inputFor('void f() {}', name: 'f');
    expect(m.compute(input), 0);
  });

  test('skips this. and super. parameters even if their field is bool', () {
    // The metric measures the *user-facing* signature. `this.x` and
    // `super.x` carry the type on the field/super declaration, not on
    // the signature, so they would not show up as `bool` to a reader of
    // the constructor head. (Unnamed constructor → no `name` argument;
    // helper falls through to the first declaration, which is the
    // constructor.)
    final input = inputFor('''
class Widget {
  final bool visible;
  final bool selected;
  Widget(this.visible, this.selected);
}
''');
    expect(m.compute(input), 0);
  });

  test('default-valued bool counts (DefaultFormalParameter wraps it)', () {
    final input = inputFor('''
void f(bool a, [bool b = false]) {}
''', name: 'f');
    expect(m.compute(input), 2);
  });

  test('rationale and refactor hints are populated', () {
    expect(m.rationale, contains('boolean'));
    expect(m.refactorHints, isNotEmpty);
    expect(m.id, 'boolean-trap');
    expect(m.defaultEnabled, isTrue);
  });
}
