import 'package:dartrics/src/metrics/function/max_nesting_level.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const m = MaxNestingLevel();

  test('flat function has depth 0', () {
    final input = inputFor('int f() => 1;', name: 'f');
    expect(m.compute(input), 0);
  });

  test('single if has depth 1', () {
    final input = inputFor('''
int f(int x) {
  if (x > 0) return 1;
  return 0;
}
''', name: 'f');
    expect(m.compute(input), 1);
  });

  test('three-deep nest reports 3', () {
    final input = inputFor('''
int f(int x) {
  for (var i = 0; i < x; i++) {
    if (i % 2 == 0) {
      while (i > 0) {
        i--;
      }
    }
  }
  return x;
}
''', name: 'f');
    expect(m.compute(input), 3);
  });

  test('named-argument closure (Widget builder) does not add a level', () {
    final input = inputFor('''
Object f() {
  return ListView.builder(
    itemCount: 3,
    itemBuilder: (context, index) {
      return Padding(padding: 8, child: index);
    },
  );
}
''', name: 'f');
    expect(m.compute(input), 0);
  });

  test('named-argument closure passes through inner control flow', () {
    final input = inputFor('''
Object f() {
  return ListView.builder(
    itemCount: 3,
    itemBuilder: (context, index) {
      if (index == 0) return 1;
      return 2;
    },
  );
}
''', name: 'f');
    expect(m.compute(input), 1);
  });

  test('named-argument closure (event handler) does not add a level', () {
    final input = inputFor('''
Object f() {
  return ElevatedButton(
    onPressed: () => 1,
    child: 'tap',
  );
}
''', name: 'f');
    expect(m.compute(input), 0);
  });

  test('positional closure still adds a level (forEach)', () {
    final input = inputFor('''
int f(List<int> xs) {
  xs.forEach((x) {
    print(x);
  });
  return xs.length;
}
''', name: 'f');
    expect(m.compute(input), 1);
  });
}
