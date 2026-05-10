import 'package:dartrics/src/metrics/function/cognitive_complexity.dart';
import 'package:dartrics/src/metrics/function/cyclomatic_complexity.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('cyclomatic complexity rare AST cases', () {
    const cc = CyclomaticComplexity();

    test('do-while contributes 1', () {
      final input = inputFor('''
int f(int x) {
  do { x--; } while (x > 0);
  return 0;
}
''', name: 'f');
      expect(cc.compute(input), 2);
    });

    test('switch with multiple cases', () {
      final input = inputFor('''
int f(int x) {
  switch (x) {
    case 1: return 1;
    case 2: return 2;
    default: return 0;
  }
}
''', name: 'f');
      // base 1 + 2 cases (default isn't counted by SwitchCase)
      expect(cc.compute(input), 3);
    });

    test('pattern switch case', () {
      final input = inputFor('''
String f(Object o) {
  switch (o) {
    case int x when x > 0: return 'pos';
    case String s: return s;
  }
  return '';
}
''', name: 'f');
      // base 1 + 2 pattern cases
      expect(cc.compute(input), 3);
    });

    test('ternary expression', () {
      final input = inputFor('''
int f(int x) {
  return x > 0 ? 1 : -1;
}
''', name: 'f');
      expect(cc.compute(input), 2);
    });

    test('function declaration nested in body is not counted', () {
      final input = inputFor('''
int f(int x) {
  int g(int y) {
    if (y > 0) return 1;
    return 0;
  }
  return g(x);
}
''', name: 'f');
      expect(cc.compute(input), 1);
    });

    test('closures inside the body do not contribute', () {
      final input = inputFor('''
int f(List<int> xs) {
  xs.where((x) => x > 0).forEach((x) {
    if (x > 5) print(x);
  });
  return 0;
}
''', name: 'f');
      // Outer body has no decisions of its own.
      expect(cc.compute(input), 1);
    });
  });

  group('cognitive complexity rare AST cases', () {
    const cog = CognitiveComplexity();

    test('do-while at depth 0 = 1', () {
      final input = inputFor('''
int f() {
  do {} while (false);
  return 0;
}
''', name: 'f');
      expect(cog.compute(input), 1);
    });

    test('switch statement at depth 0 = 1', () {
      final input = inputFor('''
int f(int x) {
  switch (x) {
    case 0: return 0;
  }
  return 1;
}
''', name: 'f');
      expect(cog.compute(input), 1);
    });

    test('switch expression at depth 0 = 1', () {
      final input = inputFor('''
String f(int x) {
  return switch (x) {
    0 => 'a',
    _ => 'b',
  };
}
''', name: 'f');
      expect(cog.compute(input), 1);
    });

    test('catch clause adds 1 + nesting', () {
      final input = inputFor('''
int f() {
  try {
    return 1;
  } catch (e) {
    return -1;
  }
}
''', name: 'f');
      expect(cog.compute(input), 1);
    });

    test('continue with label adds 1', () {
      final input = inputFor('''
int f() {
  outer: for (var i = 0; i < 3; i++) {
    for (var j = 0; j < 3; j++) {
      if (j == 1) continue outer;
    }
  }
  return 0;
}
''', name: 'f');
      // outer for: 1, inner for: 2, if: 3, continue outer: 1
      expect(cog.compute(input), 7);
    });

    test('lambda inside body increments nesting for following constructs', () {
      final input = inputFor('''
int f(List<int> xs) {
  xs.forEach((x) {
    if (x > 0) return;
  });
  return 0;
}
''', name: 'f');
      // lambda enters nesting 1; if inside lambda: 1 + 1 = 2
      expect(cog.compute(input), 2);
    });

    test('local function declaration statement enters nesting', () {
      final input = inputFor('''
int f() {
  void inner() {
    if (true) return;
  }
  inner();
  return 0;
}
''', name: 'f');
      // local fn enters nesting 1; if: 1 + 1 = 2
      expect(cog.compute(input), 2);
    });

    test('while loop adds 1 + nesting', () {
      final input = inputFor('''
int f(int x) {
  while (x > 0) {
    x--;
  }
  return 0;
}
''', name: 'f');
      expect(cog.compute(input), 1);
    });

    test('ternary adds 1 + nesting', () {
      final input = inputFor(
        'int f(int x) { return x > 0 ? 1 : -1; }',
        name: 'f',
      );
      expect(cog.compute(input), 1);
    });
  });
}
