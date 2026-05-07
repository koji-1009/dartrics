import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../metric.dart';

/// Async chain depth — the deepest nesting of `await` expressions found
/// inside the function body.
///
/// `await foo(await bar(await baz()))` reads at depth 3: each inner
/// `await` is suspended on the result of an outer `await`, which makes
/// the dataflow harder to follow than a sequential ladder of awaits
/// (`final a = await foo(); final b = await bar(a);`). The metric does
/// **not** count sequential awaits — only nested ones — because the
/// readability cost is specifically the "what's resolved when" stack
/// the reader has to maintain.
///
/// Off by default — projects with a heavy synchronous control-flow
/// style won't touch nested awaits at all, and the threshold (default
/// warning 3) needs tuning per codebase. Detection is purely AST: the
/// visitor pushes on each `AwaitExpression` and pops on the way out,
/// recording the maximum depth seen on any single path. Closures
/// (`forEach((x) async => await x.send())`) are treated as separate
/// scopes — the async chain is reset for each closure body.
class AsyncChainDepth extends FunctionMetric {
  const AsyncChainDepth();

  @override
  String get id => 'async-chain-depth';

  @override
  bool get defaultEnabled => false;

  @override
  String get rationale =>
      'Async chain depth measures the deepest nesting of `await` '
      'expressions in the function body. `await foo(await bar(await '
      'baz()))` reads at depth 3 — each inner await suspends on the '
      'result of an outer await, which forces the reader to maintain '
      'a "what resolves when" stack. Sequential awaits like `final a '
      '= await foo(); final b = await bar(a);` are not counted: only '
      'nested awaits add to the chain. Default warning 3 catches the '
      'spots where pulling the inner await into a local variable or '
      'awaiting `Future.wait` would flatten the structure.';

  @override
  List<String> get refactorHints => const [
    'Pull the inner `await` into a `final x = await ...;` local; the outer call then takes `x` as a plain value.',
    'When several awaits can run in parallel, replace the chain with `await Future.wait([...])` so the dataflow is independent.',
    'If a deep chain captures a sequence of dependent operations, extract them into a named async helper so the caller reads as one step.',
  ];

  @override
  num compute(FunctionMetricInput input) {
    final visitor = _AsyncChainVisitor();
    input.body.accept(visitor);
    return visitor.maxDepth;
  }
}

/// Tracks the deepest stack of nested `AwaitExpression` nodes on any
/// path through the body. Closures reset the depth — they're a
/// separate async scope.
class _AsyncChainVisitor extends RecursiveAstVisitor<void> {
  int _currentDepth = 0;
  int maxDepth = 0;

  @override
  void visitAwaitExpression(AwaitExpression node) {
    _currentDepth++;
    if (_currentDepth > maxDepth) maxDepth = _currentDepth;
    super.visitAwaitExpression(node);
    _currentDepth--;
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // A closure is its own async scope: the depth at the closure
    // boundary doesn't carry into the closure body. Save / restore
    // so a `await foo((x) async { await bar(x); })` doesn't get
    // counted as depth 2 from the outer await.
    final saved = _currentDepth;
    _currentDepth = 0;
    super.visitFunctionExpression(node);
    _currentDepth = saved;
  }
}
