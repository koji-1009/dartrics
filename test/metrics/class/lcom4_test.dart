import 'package:dartrics/src/metrics/class/lcom4.dart';
import 'package:test/test.dart';

import 'class_helpers.dart';

void main() {
  const m = Lcom4();

  test('cohesive class — one component', () {
    final input = inputFor('''
class Counter {
  int _value = 0;
  void inc() { _value++; }
  void dec() { _value--; }
  int get value => _value;
}
''', className: 'Counter');
    expect(m.compute(input), 1);
  });

  test('two unrelated method groups → two components', () {
    final input = inputFor('''
class Mixed {
  int _a = 0;
  String _b = '';
  void touchA() { _a += 1; }
  int readA() { return _a; }
  void touchB() { _b += 'x'; }
  String readB() { return _b; }
}
''', className: 'Mixed');
    // Methods touching _a form one component; methods touching _b form a
    // second component. → 2
    expect(m.compute(input), 2);
  });

  test('method calls bridge components', () {
    final input = inputFor('''
class Bridged {
  int _a = 0;
  String _b = '';
  void touchA() { _a += 1; }
  void touchB() { _b += 'x'; touchA(); }  // call bridges to _a's group
  int readA() { return _a; }
  String readB() { return _b; }
}
''', className: 'Bridged');
    // Single component because touchB calls touchA.
    expect(m.compute(input), 1);
  });

  test('single-method class returns 1', () {
    final input = inputFor('''
class Lonely {
  void only() {}
}
''', className: 'Lonely');
    expect(m.compute(input), 1);
  });
}
