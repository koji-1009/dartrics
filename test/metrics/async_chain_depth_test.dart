import 'package:dartrics/src/metrics/function/async_chain_depth.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const m = AsyncChainDepth();

  test('synchronous body reports 0', () {
    final input = inputFor(r'''
int f(int a) => a + 1;
''', name: 'f');
    expect(m.compute(input), 0);
  });

  test('a single top-level await reports 1', () {
    final input = inputFor(r'''
Future<int> f() async {
  return await foo();
}
''', name: 'f');
    expect(m.compute(input), 1);
  });

  test('sequential awaits stay at depth 1 (not nested)', () {
    final input = inputFor(r'''
Future<int> f() async {
  final a = await foo();
  final b = await bar(a);
  return b;
}
''', name: 'f');
    expect(m.compute(input), 1);
  });

  test('two-level nested await reports depth 2', () {
    final input = inputFor(r'''
Future<int> f() async {
  return await foo(await bar());
}
''', name: 'f');
    expect(m.compute(input), 2);
  });

  test('three-level nested await reports depth 3', () {
    final input = inputFor(r'''
Future<int> f() async {
  return await foo(await bar(await baz()));
}
''', name: 'f');
    expect(m.compute(input), 3);
  });

  test('mixed: deeper nest in one place wins', () {
    final input = inputFor(r'''
Future<int> f() async {
  final a = await foo();
  return await bar(await baz(await qux()));
}
''', name: 'f');
    expect(m.compute(input), 3);
  });

  test('closure body is its own async scope', () {
    // The outer `await items.fold(...)` is depth 1; the closure's
    // own body has depth 1 (one `await item.send()`), but the
    // closure boundary stops the outer depth from compounding.
    // The visitor saves/restores depth across the closure so we
    // see depth 1, not 2.
    final input = inputFor(r'''
Future<void> f(List items) async {
  await items.fold(0, (acc, item) async => await item.send());
}
''', name: 'f');
    expect(m.compute(input), 1);
  });

  test('default-off, rationale + hints populated', () {
    expect(m.id, 'async-chain-depth');
    expect(m.defaultEnabled, isFalse);
    expect(m.rationale.toLowerCase(), contains('await'));
    expect(m.refactorHints, isNotEmpty);
  });
}
