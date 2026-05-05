import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../metric.dart';

/// Cyclomatic Complexity (McCabe, 1976) — `1 + d` where `d` is the number of
/// linearly independent decision points in the control-flow graph.
///
/// In practice each of the following adds 1: `if`, `for`, `while`, `do`,
/// `switch case` (one per non-default arm), `catch`, ternary `?:`, and the
/// short-circuit operators `&&` / `||`. Nested closures are measured
/// separately and do **not** contribute to the enclosing function's value.
///
/// Reference: McCabe, T.J. *A Complexity Measure*, IEEE TSE, 1976.
class CyclomaticComplexity implements FunctionMetric {
  const CyclomaticComplexity();

  @override
  String get id => 'cyclomatic-complexity';

  @override
  num compute(FunctionMetricInput input) {
    final visitor = _CyclomaticVisitor();
    input.body.accept(visitor);
    return 1 + visitor.count;
  }
}

class _CyclomaticVisitor extends RecursiveAstVisitor<void> {
  int count = 0;
  bool _enteredRootBody = false;

  // Skip nested closures: only descend into the first body we encounter.
  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (!_enteredRootBody) {
      _enteredRootBody = true;
      super.visitFunctionExpression(node);
    }
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    // Local function declarations inside the body — skip; they have their
    // own CC.
  }

  @override
  void visitIfStatement(IfStatement node) {
    count++;
    super.visitIfStatement(node);
  }

  @override
  void visitForStatement(ForStatement node) {
    count++;
    super.visitForStatement(node);
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    count++;
    super.visitWhileStatement(node);
  }

  @override
  void visitDoStatement(DoStatement node) {
    count++;
    super.visitDoStatement(node);
  }

  @override
  void visitSwitchPatternCase(SwitchPatternCase node) {
    count++;
    super.visitSwitchPatternCase(node);
  }

  @override
  void visitCatchClause(CatchClause node) {
    count++;
    super.visitCatchClause(node);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    count++;
    super.visitConditionalExpression(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final op = node.operator.lexeme;
    if (op == '&&' || op == '||') count++;
    super.visitBinaryExpression(node);
  }
}
