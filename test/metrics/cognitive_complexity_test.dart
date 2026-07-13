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

  test('if-case `when` guard contents are scored', () {
    final input = inputFor('''
int f(Object x, bool a, bool b) {
  if (x case int i when a && b) {
    return i;
  }
  return 0;
}
''', name: 'f');
    // if: 1 (1+0); `&&` sequence inside the guard: 1 (B3).
    expect(cog.compute(input), 2);
  });

  test('ternary inside an if-case guard nests under the if', () {
    final input = inputFor('''
int f(Object x, bool a) {
  if (x case int i when (a ? i : -i) > 0) {
    return i;
  }
  return 0;
}
''', name: 'f');
    // if: 1 (1+0); guard ternary: 1 + nesting 0 (the guard is part of
    // the if header, before the body's nesting increment) = 1.
    expect(cog.compute(input), 2);
  });

  group('test-DSL discount (isTestFile)', () {
    // Without the discount, every branch inside every test body accrues
    // to main() at +2 nesting through the group()/test() closure stack.
    const dslSource = '''
void main() {
  group('runs', () {
    test('a', () {
      if (kIsWeb) return;
      for (var i = 0; i < 3; i++) {
        if (i == 2) check(i);
      }
    });
    test('b', () {
      if (kIsWeb) return;
    });
  });
}
''';

    test('argument closures do not accrue to main on test files', () {
      final input = inputFor(dslSource, name: 'main', isTestFile: true);
      // The group()/test() callbacks are registration data, not control
      // flow of main — main's own flow is straight-line.
      expect(cog.compute(input), 0);
    });

    test('production files keep the spec behavior (regression guard)', () {
      final input = inputFor(dslSource, name: 'main');
      // group closure: nesting 1; test closures: nesting 2.
      // test 'a': if (1+2) + for (1+2) + if (1+3) = 10
      // test 'b': if (1+2) = 3
      expect(cog.compute(input), 13);
    });

    test('named-argument closures are also skipped on test files', () {
      final input = inputFor(
        '''
void main() {
  run(onError: (e) {
    if (e is StateError) rethrow;
  });
}
''',
        name: 'main',
        isTestFile: true,
      );
      expect(cog.compute(input), 0);
    });

    test("main's own control flow stays scored on test files", () {
      final input = inputFor(
        '''
void main() {
  for (final c in cases) {
    test(c.name, () {
      if (c.skip) return;
    });
  }
}
''',
        name: 'main',
        isTestFile: true,
      );
      // The parameterizing for-loop is main's own flow: 1 + 0 = 1.
      // The test callback's if is registration data: skipped.
      expect(cog.compute(input), 1);
    });

    test('non-argument closures still accrue on test files', () {
      final input = inputFor(
        '''
void main() {
  final check = (int x) {
    if (x > 0) print(x);
  };
  check(1);
}
''',
        name: 'main',
        isTestFile: true,
      );
      // Closure assigned to a local is read inline, not handed to a
      // DSL — its if is charged at nesting 1: 1 + 1 = 2.
      expect(cog.compute(input), 2);
    });
  });
}
