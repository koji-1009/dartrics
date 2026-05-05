import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../metric.dart';

/// Maximum Nesting Level — the deepest depth of nested control-flow blocks
/// in the function body.
///
/// Counted constructs: `if`, `for`, `while`, `do`, `switch`, `try`/`catch`,
/// and lambda/closure bodies. Not part of any single canonical paper; deep
/// nesting is well-correlated with bug density (e.g. NIST 500-235 §4) and is
/// a common metric in PMD, Checkstyle, and SonarLint.
class MaxNestingLevel implements FunctionMetric {
  const MaxNestingLevel();

  @override
  String get id => 'maximum-nesting-level';

  @override
  num compute(FunctionMetricInput input) {
    final body = input.body;
    if (body == null) return 0;
    final visitor = _NestingVisitor();
    body.accept(visitor);
    return visitor.maxDepth;
  }
}

class _NestingVisitor extends RecursiveAstVisitor<void> {
  int currentDepth = 0;
  int maxDepth = 0;

  void _enter() {
    currentDepth++;
    if (currentDepth > maxDepth) maxDepth = currentDepth;
  }

  void _exit() => currentDepth--;

  @override
  void visitIfStatement(IfStatement node) {
    _enter();
    super.visitIfStatement(node);
    _exit();
  }

  @override
  void visitForStatement(ForStatement node) {
    _enter();
    super.visitForStatement(node);
    _exit();
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    _enter();
    super.visitWhileStatement(node);
    _exit();
  }

  @override
  void visitDoStatement(DoStatement node) {
    _enter();
    super.visitDoStatement(node);
    _exit();
  }

  @override
  void visitSwitchStatement(SwitchStatement node) {
    _enter();
    super.visitSwitchStatement(node);
    _exit();
  }

  @override
  void visitSwitchExpression(SwitchExpression node) {
    _enter();
    super.visitSwitchExpression(node);
    _exit();
  }

  @override
  void visitTryStatement(TryStatement node) {
    _enter();
    super.visitTryStatement(node);
    _exit();
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // Closures introduce a visual nesting level for the reader; only the
    // *outer* function gets credited here. Nested function metrics are
    // computed separately when the engine visits their declarations.
    if (node.parent is ExpressionFunctionBody ||
        node.parent is BlockFunctionBody ||
        node.parent is FunctionDeclaration) {
      // This is the body's own FunctionExpression — don't count.
      super.visitFunctionExpression(node);
      return;
    }
    _enter();
    super.visitFunctionExpression(node);
    _exit();
  }
}
