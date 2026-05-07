import 'package:dartrics/src/metrics/function/widget_tree_depth.dart';
import 'package:dartrics/src/metrics/metric.dart';
import 'package:test/test.dart';

import 'helpers.dart';

// `parseString` (used by `inputFor`) doesn't resolve, so the parser
// can't disambiguate `Container()` from a top-level method call —
// modern Dart syntax sugar drops `new`. Test fixtures use `const` /
// `new` keywords explicitly to force `InstanceCreationExpression` at
// the parser level. In production, `MetricEngine` feeds resolved
// units so even un-keyword'd `Container()` parses as a constructor
// call; the metric implementation handles both because it visits
// only `InstanceCreationExpression`.

void main() {
  const m = WidgetTreeDepth();

  test('flat function with no constructor calls reports 0', () {
    final input = inputFor(r'''
int add(int a, int b) {
  return a + b;
}
''', name: 'add');
    expect(m.compute(input), 0);
  });

  test('single-level constructor call reports 1', () {
    final input = inputFor(r'''
class Container { const Container({this.child}); final Container? child; }
Container build() {
  return const Container();
}
''', name: 'build');
    expect(m.compute(input), 1);
  });

  test('nested Widget tree reports the deepest chain', () {
    // Explicit `const` on every level so unresolved parseString lands
    // each as InstanceCreationExpression. In real (resolved) builds,
    // implicit-const propagation makes the inner `const` keywords
    // unnecessary; this fixture is a parser-level workaround.
    final input = inputFor(r'''
class Container { const Container({this.child}); final Container? child; }
Container build() {
  return const Container(
    child: const Container(
      child: const Container(
        child: const Container(),
      ),
    ),
  );
}
''', name: 'build');
    expect(m.compute(input), 4);
  });

  test('parallel siblings do not stack', () {
    final input = inputFor(r'''
class Row { const Row({this.children}); final List? children; }
class Container { const Container(); }
Row build() {
  return const Row(
    children: [const Container(), const Container(), const Container()],
  );
}
''', name: 'build');
    expect(m.compute(input), 2);
  });

  test('builder closure adds further depth on the contained tree', () {
    final input = inputFor(r'''
class Builder { const Builder({this.builder}); final Object? Function(Object)? builder; }
class Container { const Container({this.child}); final Container? child; }
Builder build() {
  return Builder(
    builder: (ctx) => const Container(child: const Container()),
  );
}
''', name: 'build');
    // The `Builder(...)` outer call is unresolved-parsed as a
    // MethodInvocation (no `const`), so it doesn't count against
    // depth. The closure body's chain is `Container > Container` = 2.
    expect(m.compute(input), 2);
  });

  test('method-call chains do not contribute to depth', () {
    // EdgeInsets(...).copyWith(...) — the constructor counts as 1, the
    // copyWith is a method call so it doesn't stack.
    final input = inputFor(r'''
class EdgeInsets {
  const EdgeInsets({this.top, this.bottom});
  EdgeInsets copyWith({double? top}) => EdgeInsets(top: top, bottom: bottom);
  final double? top;
  final double? bottom;
}
EdgeInsets build() {
  return const EdgeInsets(top: 8.0).copyWith(top: 16.0);
}
''', name: 'build');
    expect(m.compute(input), 1);
  });

  test('default-off, polarity down, rationale + hints non-empty', () {
    expect(m.id, 'widget-tree-depth');
    expect(m.defaultEnabled, isFalse);
    expect(m.polarity, MetricPolarity.down);
    expect(m.rationale.toLowerCase(), contains('widget tree'));
    expect(m.refactorHints, isNotEmpty);
  });
}
