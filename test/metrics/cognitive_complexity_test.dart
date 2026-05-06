import 'package:dartrics/src/metrics/function/cognitive_complexity.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const cog = CognitiveComplexity();

  test('straight-line function has score = 0', () {
    final input = inputFor('''
int add(int a, int b) => a + b;
''', name: 'add');
    expect(cog.compute(input), 0);
  });

  test('single if at top level adds 1 (1 + nesting=0)', () {
    final input = inputFor('''
int sign(int x) {
  if (x > 0) return 1;
  return 0;
}
''', name: 'sign');
    expect(cog.compute(input), 1);
  });

  test('nested if adds nesting penalty', () {
    final input = inputFor('''
int f(int x, int y) {
  if (x > 0) {
    if (y > 0) return 1;
  }
  return 0;
}
''', name: 'f');
    // outer if: 1 + 0 = 1
    // inner if: 1 + 1 = 2
    expect(cog.compute(input), 3);
  });

  test('else if cascades flat (no nesting penalty per branch)', () {
    final input = inputFor('''
String f(int x) {
  if (x == 0) return 'a';
  else if (x == 1) return 'b';
  else if (x == 2) return 'c';
  else return 'd';
}
''', name: 'f');
    // outer if: 1, else if (flat): 1, else if (flat): 1, else (flat): 1
    expect(cog.compute(input), 4);
  });

  test('binary logical sequences only count once per same-operator run', () {
    final input = inputFor('''
bool same(bool a, bool b, bool c, bool d) {
  return a && b && c && d;
}
''', name: 'same');
    expect(cog.compute(input), 1);
  });

  test('mixed && / || count per distinct sequence', () {
    final input = inputFor('''
bool mixed(bool a, bool b, bool c) {
  return a && b || c;
}
''', name: 'mixed');
    expect(cog.compute(input), 2);
  });

  test('break with label adds 1', () {
    final input = inputFor('''
int loops() {
  outer: for (var i = 0; i < 10; i++) {
    for (var j = 0; j < 10; j++) {
      if (j == 5) break outer;
    }
  }
  return 0;
}
''', name: 'loops');
    // outer for: 1 (1+0)
    // inner for: 2 (1+1)
    // if: 3 (1+2)
    // break label: 1
    expect(cog.compute(input), 7);
  });
}
