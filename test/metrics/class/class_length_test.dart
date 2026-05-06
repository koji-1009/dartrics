import 'package:dartrics/src/metrics/class/class_length.dart';
import 'package:test/test.dart';

import 'class_helpers.dart';

void main() {
  const m = ClassLength();

  test('one-line class spans 1 line', () {
    final input = inputFor('class A {}', className: 'A');
    expect(m.compute(input), 1);
  });

  test('multi-line class counts every line in the declaration', () {
    final input = inputFor('''
class A {
  int x = 0;

  void foo() {}
}
''', className: 'A');
    // class header + body content + closing brace = 5 lines
    expect(m.compute(input), 5);
  });
}
