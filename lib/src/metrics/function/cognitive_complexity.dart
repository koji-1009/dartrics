import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../metric.dart';

/// Cognitive Complexity (G. Ann Campbell, SonarSource 2018).
///
/// Differs from Cyclomatic Complexity by reflecting the difficulty of
/// understanding control flow rather than the difficulty of testing it.
/// Three rule families:
///
/// - **B1** Increment for *each* control-flow break: `if`, `else if`, `else`,
///   ternary, `switch`, `for`, `while`, `do`, `catch`, jumps with labels.
/// - **B2** Add the current nesting level on top of B1 for the constructs
///   that also nest: `if`, ternary, `switch`, `for`, `while`, `do`, `catch`.
/// - **B3** Each *sequence* of like binary logical operators (`&&` or `||`)
///   contributes 1, regardless of nesting.
///
/// Nested method/lambda declarations increase the nesting depth but do not
/// themselves contribute to the score. The outer method's score is computed
/// independently of inner methods (each function gets its own score).
///
/// Reference: G. Ann Campbell, *Cognitive Complexity — A new way of measuring
/// understandability*, SonarSource white paper, 2018.
class CognitiveComplexity extends FunctionMetric {
  const CognitiveComplexity();

  @override
  String get id => 'cognitive-complexity';

  @override
  String get rationale =>
      'Campbell (SonarSource, 2018) introduces cognitive complexity to '
      'reflect "how hard the control flow is to understand" rather than '
      '"how hard it is to test". Three rule families add to the score: '
      '(B1) every break in linear flow adds 1, (B2) nesting-aware '
      'constructs additionally add the current nesting depth, and (B3) '
      'each chain of like logical operators adds 1. Unlike cyclomatic '
      'complexity, deeply-nested code is penalized more than flat code '
      'with the same number of branches, which is closer to a human '
      'reviewer\'s experience. A common starting threshold is 15.';

  @override
  List<String> get refactorHints => const [
    'Flatten nesting by inverting conditions and returning early.',
    'Hoist nested loops or conditionals into well-named helpers; the name carries the cognitive load.',
    'Combine `&&` / `||` chains into a single boolean variable with an explanatory name.',
    'Replace recursive nested branches with table-driven dispatch when the structure is regular.',
  ];

  @override
  List<String> get references => const [
    'Campbell, G. A. (2018). Cognitive Complexity: A new way of measuring understandability. SonarSource technical paper.',
  ];

  @override
  num compute(FunctionMetricInput input) {
    final visitor = _CognitiveVisitor();
    input.body.accept(visitor);
    return visitor.score;
  }
}

class _CognitiveVisitor extends RecursiveAstVisitor<void> {
  int score = 0;
  int nesting = 0;

  void _structuralWithNesting() {
    score += 1 + nesting;
  }

  void _structuralFlat() {
    score += 1;
  }

  void _enterNesting() => nesting++;
  void _exitNesting() => nesting--;

  @override
  void visitIfStatement(IfStatement node) {
    final isElseIf =
        node.parent is IfStatement &&
        (node.parent as IfStatement).elseStatement == node;
    if (isElseIf) {
      _structuralFlat();
    } else {
      _structuralWithNesting();
    }
    node.expression.accept(this);
    _enterNesting();
    node.thenStatement.accept(this);
    _exitNesting();

    final elseStmt = node.elseStatement;
    if (elseStmt != null) {
      if (elseStmt is IfStatement) {
        // The else-if recursion will increment for the inner `if`.
        elseStmt.accept(this);
      } else {
        _structuralFlat();
        _enterNesting();
        elseStmt.accept(this);
        _exitNesting();
      }
    }
  }

  @override
  void visitForStatement(ForStatement node) {
    _structuralWithNesting();
    _enterNesting();
    super.visitForStatement(node);
    _exitNesting();
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    _structuralWithNesting();
    _enterNesting();
    super.visitWhileStatement(node);
    _exitNesting();
  }

  @override
  void visitDoStatement(DoStatement node) {
    _structuralWithNesting();
    _enterNesting();
    super.visitDoStatement(node);
    _exitNesting();
  }

  @override
  void visitSwitchStatement(SwitchStatement node) {
    _structuralWithNesting();
    _enterNesting();
    super.visitSwitchStatement(node);
    _exitNesting();
  }

  @override
  void visitSwitchExpression(SwitchExpression node) {
    _structuralWithNesting();
    _enterNesting();
    super.visitSwitchExpression(node);
    _exitNesting();
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    _structuralWithNesting();
    _enterNesting();
    super.visitConditionalExpression(node);
    _exitNesting();
  }

  @override
  void visitCatchClause(CatchClause node) {
    _structuralWithNesting();
    _enterNesting();
    super.visitCatchClause(node);
    _exitNesting();
  }

  @override
  void visitBreakStatement(BreakStatement node) {
    if (node.label != null) _structuralFlat();
    super.visitBreakStatement(node);
  }

  @override
  void visitContinueStatement(ContinueStatement node) {
    if (node.label != null) _structuralFlat();
    super.visitContinueStatement(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final op = node.operator.lexeme;
    if (op == '&&' || op == '||') {
      // First in a sequence (parent isn't the same operator) → +1.
      final parent = node.parent;
      final sameOpAsParent =
          parent is BinaryExpression && parent.operator.lexeme == op;
      if (!sameOpAsParent) score += 1;
    }
    super.visitBinaryExpression(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (node.parent is FunctionDeclaration) {
      // The wrapping FunctionDeclaration (top-level or local) is the
      // bookkeeping unit for nesting; counting the inner expression too
      // would double-charge a nested method/lambda.
      super.visitFunctionExpression(node);
      return;
    }
    _enterNesting();
    super.visitFunctionExpression(node);
    _exitNesting();
  }

  @override
  void visitFunctionDeclarationStatement(FunctionDeclarationStatement node) {
    _enterNesting();
    super.visitFunctionDeclarationStatement(node);
    _exitNesting();
  }
}
