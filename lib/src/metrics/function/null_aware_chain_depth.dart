import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../metric.dart';

/// Null-aware chain depth — the longest chain of `?.` operators in any
/// expression inside the function body.
///
/// `a?.b?.c?.d?.e` reads at depth 5: each `?.` adds a "if the previous
/// step was non-null" guard the reader has to hold in working memory.
/// `maximum-nesting-level` doesn't catch this because the chain is one
/// expression, not nested control flow. Cognitive complexity catches
/// part of it via B3 (logical-op sequences) but treats `?.` like any
/// other operator. This lens singles out the chain depth so deep null
/// guards get their own actionable signal.
///
/// Off by default — Dart 2's `?.` was lifted into a more flexible chain
/// in Dart 3, and project conventions vary widely on how deep is too
/// deep. Default warning threshold is 4.
///
/// Detection is purely lexical on the AST. It walks every chained
/// `PropertyAccess` / `MethodInvocation` / `IndexExpression` node and
/// counts the operators along each chain that carry the `?.` form.
class NullAwareChainDepth extends FunctionMetric {
  const NullAwareChainDepth();

  @override
  String get id => 'null-aware-chain-depth';

  @override
  bool get defaultEnabled => false;

  @override
  String get rationale =>
      'Null-aware chain depth counts the longest chain of `?.` '
      'operators in any expression inside the function body. Each '
      '`?.` step is an implicit "if the previous result was non-null" '
      'guard that the reader has to hold in working memory; deep '
      'chains (`a?.b?.c?.d?.e`) read as conditional dataflow that '
      'neither `maximum-nesting-level` nor the basic `cognitive-'
      'complexity` rules surface separately. Off by default because '
      'project conventions vary on what counts as "too deep"; '
      'opt in with a threshold tuned for your codebase. A starting '
      'warning of 4 catches the spots where extracting an early-return '
      'guard or a local variable would clean up the chain.';

  @override
  List<String> get refactorHints => const [
    'Hoist the result of the chain prefix into a local with an early-return guard: `final x = a?.b; if (x == null) return ...; use(x.c?.d);`.',
    'Replace deep null-aware chains with a typed `Result` / `Option` value or a method on the leaf object that does the unwrap.',
    'When the chain spans business logic (not just navigation), promote a method on the closest type that owns the operation.',
  ];

  @override
  num compute(FunctionMetricInput input) {
    final visitor = _ChainDepthVisitor();
    input.body.accept(visitor);
    return visitor.maxDepth;
  }
}

/// Walks every chainable expression and tracks the longest sequence
/// of `?.` operators on a single chain.
class _ChainDepthVisitor extends RecursiveAstVisitor<void> {
  int maxDepth = 0;

  @override
  void visitPropertyAccess(PropertyAccess node) {
    _measureChain(node);
    super.visitPropertyAccess(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _measureChain(node);
    super.visitMethodInvocation(node);
  }

  /// Walks the chain rooted at [tail] from leaf back to root, counting
  /// every `?.` operator. The Dart parser builds chains right-leaning
  /// (`a.b.c.d` parses as `((a.b).c).d`), so following `.target` from
  /// the outermost node hits each link in turn.
  void _measureChain(Expression tail) {
    var depth = 0;
    Expression? cursor = tail;
    while (true) {
      final step = _stepInChain(cursor);
      if (step == null) break;
      if (step.isNullAware) depth++;
      cursor = step.target;
    }
    if (depth > maxDepth) maxDepth = depth;
  }

  /// Reads the chain link at [cursor] and returns its `?.` flag plus
  /// the previous link (`target`). Returns `null` when [cursor] is not
  /// a chainable expression — the caller treats that as the end of the
  /// chain and stops walking.
  ({bool isNullAware, Expression? target})? _stepInChain(Expression? cursor) {
    if (cursor is PropertyAccess) {
      return (isNullAware: cursor.isNullAware, target: cursor.target);
    }
    if (cursor is MethodInvocation) {
      return (isNullAware: cursor.isNullAware, target: cursor.target);
    }
    return null;
  }
}
