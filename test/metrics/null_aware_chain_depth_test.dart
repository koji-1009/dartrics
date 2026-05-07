import 'package:dartrics/src/metrics/function/null_aware_chain_depth.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const m = NullAwareChainDepth();

  test('flat function with no null-aware operators reports 0', () {
    final input = inputFor(r'''
int f(int a, int b) {
  return a + b;
}
''', name: 'f');
    expect(m.compute(input), 0);
  });

  test('plain (non-null-aware) chain reports 0', () {
    final input = inputFor(r'''
int f(dynamic a) => a.b.c.d.e;
''', name: 'f');
    expect(m.compute(input), 0);
  });

  test('a single ?. step reports 1', () {
    final input = inputFor(r'''
int? f(dynamic a) => a?.length;
''', name: 'f');
    expect(m.compute(input), 1);
  });

  test('mixed `.` / `?.` chain counts only the ?. links', () {
    final input = inputFor(r'''
int? f(dynamic a) => a.b?.c.d?.e;
''', name: 'f');
    expect(m.compute(input), 2);
  });

  test('deep ?. chain reports its full length', () {
    final input = inputFor(r'''
int? f(dynamic a) => a?.b?.c?.d?.e;
''', name: 'f');
    expect(m.compute(input), 4);
  });

  test('null-aware method invocations count too', () {
    final input = inputFor(r'''
int? f(dynamic a) => a?.foo()?.bar()?.baz();
''', name: 'f');
    expect(m.compute(input), 3);
  });

  test('two separate chains pick the deepest one', () {
    final input = inputFor(r'''
int f(dynamic a, dynamic b) {
  final x = a?.b?.c;       // depth 2
  final y = b?.x?.y?.z?.w; // depth 4
  return (x ?? 0) + (y ?? 0);
}
''', name: 'f');
    expect(m.compute(input), 4);
  });

  test('default-off, polarity down, rationale + hints populated', () {
    expect(m.id, 'null-aware-chain-depth');
    expect(m.defaultEnabled, isFalse);
    expect(m.rationale.toLowerCase(), contains('null-aware'));
    expect(m.refactorHints, isNotEmpty);
  });
}
