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
class CyclomaticComplexity extends FunctionMetric {
  const CyclomaticComplexity();

  @override
  String get id => 'cyclomatic-complexity';

  @override
  String get rationale =>
      'McCabe (1976) defines cyclomatic complexity as the number of '
      'linearly independent paths through a function. It is computed as '
      '`1 + d`, where `d` is the count of decision points (`if`, `for`, '
      '`while`, `do`, `case` arm, `catch`, ternary, `&&`, `||`). The '
      'value is also a lower bound on the number of test cases needed to '
      'cover every branch, which is why teams use it as a structural-cost '
      'signal. The default warning threshold of 10 follows McCabe\'s '
      'original recommendation that "10 seems like a reasonable, but not '
      'magical, upper limit".';

  @override
  List<String> get refactorHints => const [
    'Extract long branches into helper functions named after their intent.',
    'Replace nested `if` chains with early-return guard clauses.',
    'Replace large `switch`/`if-else` ladders with a lookup table or polymorphic dispatch.',
    'Split the function along its independent responsibilities — high CC is often a hint that one body is doing two jobs.',
  ];

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
