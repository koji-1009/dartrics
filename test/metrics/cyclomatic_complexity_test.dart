import 'package:dartrics/src/metrics/function/cyclomatic_complexity.dart';
import 'package:test/test.dart';

import '_helpers.dart';

void main() {
  const cc = CyclomaticComplexity();

  test('straight-line function has CC = 1', () {
    final input = inputFor('''
int add(int a, int b) {
  return a + b;
}
''', name: 'add');
    expect(cc.compute(input), 1);
  });

  test('single if adds 1', () {
    final input = inputFor('''
int sign(int x) {
  if (x > 0) return 1;
  return 0;
}
''', name: 'sign');
    expect(cc.compute(input), 2);
  });

  test('classic Euclidean algorithm (one while) has CC = 2', () {
    final input = inputFor('''
int gcd(int a, int b) {
  while (b != 0) {
    final r = a % b;
    a = b;
    b = r;
  }
  return a;
}
''', name: 'gcd');
    expect(cc.compute(input), 2);
  });

  test('nested decisions and short-circuit operators all count', () {
    final input = inputFor('''
int classify(int x, int y) {
  if (x > 0 && y > 0) {
    if (x > y) return 1;
    return 2;
  }
  for (var i = 0; i < x; i++) {
    if (i % 2 == 0) continue;
  }
  try {
    return x ~/ y;
  } catch (_) {
    return -1;
  }
}
''', name: 'classify');
    // 1 (base)
    // + 1 (if x>0 && y>0)
    // + 1 (&& inside the condition)
    // + 1 (if x > y)
    // + 1 (for)
    // + 1 (if i%2==0)
    // + 1 (catch)
    expect(cc.compute(input), 7);
  });

  test('nested functions are measured separately', () {
    final input = inputFor('''
int outer(int x) {
  int inner(int y) {
    if (y > 0) return 1;
    return 0;
  }
  return inner(x);
}
''', name: 'outer');
    expect(cc.compute(input), 1, reason: 'inner if must not affect outer CC');
  });
}
