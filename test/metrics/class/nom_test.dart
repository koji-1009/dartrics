import 'package:dartrics/src/metrics/class/nom.dart';
import 'package:test/test.dart';

import 'class_helpers.dart';

void main() {
  const m = NumberOfMethods();

  test('counts methods, getters, setters, and constructors with bodies', () {
    final input = inputFor('''
class C {
  int? _v;
  C() { _v = 0; }
  C.named(this._v);  // empty body — counted? No: empty body excluded.
  int get value => _v ?? 0;
  set value(int x) { _v = x; }
  int compute() { return _v ?? 0; }
  void abstractDecl();  // empty body — excluded.
}
''', className: 'C');
    // C() body, value getter (=>), value setter, compute() — 4
    expect(m.compute(input), 4);
  });

  test('zero-method class returns 0', () {
    final input = inputFor('''
class Empty {
  final int x;
  Empty(this.x);
}
''', className: 'Empty');
    // Empty(this.x) is a redirecting/forwarding ctor with empty body. 0.
    expect(m.compute(input), 0);
  });
}
