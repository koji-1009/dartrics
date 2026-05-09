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
class MaxNestingLevel extends FunctionMetric {
  const MaxNestingLevel();

  @override
  String get id => 'maximum-nesting-level';

  @override
  String get rationale =>
      'Maximum nesting level counts the deepest depth of nested control '
      'flow inside the function body (`if`, `for`, `while`, `do`, '
      '`switch`, `try`/`catch`, plus closure bodies). Empirical work '
      'such as NIST 500-235 §4 reports a strong correlation between '
      'nesting depth and bug density, which is why PMD, Checkstyle, and '
      'SonarLint all ship a variant of it. A typical warning threshold '
      'is 4: code one level past that usually wants extracting.';

  @override
  List<String> get refactorHints => const [
    'Invert the outer condition and return early to drop one level.',
    'Extract the deepest block into a named helper.',
    'Replace nested loops with iterator combinators (`map`/`where`/`fold`) when the body is small.',
    'Move guard checks above the main work to flatten the happy path.',
  ];

  @override
  List<String> get references => const [
    'NIST Special Publication 500-235 §4 — Structured Testing: A Testing Methodology Using the Cyclomatic Complexity Metric (1996).',
  ];

  @override
  num compute(FunctionMetricInput input) {
    final visitor = _NestingVisitor();
    input.body.accept(visitor);
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
    if (node.parent is FunctionDeclaration) {
      // Local function declaration (`void inner() {}` inside a body) —
      // measured separately by the engine on its own pass; don't descend
      // into its statements when computing the outer function's nesting.
      return;
    }
    if (node.parent is NamedArgument) {
      // Named-argument closure (`ListView.builder(itemBuilder: (...) {})`,
      // `ElevatedButton(onPressed: () {})`, …) is declarative
      // configuration — a Widget builder or an event handler — not a
      // control-flow nesting level. Descend without incrementing so any
      // inner `if` / `for` still counts at the right depth, but the
      // closure boundary itself doesn't.
      super.visitFunctionExpression(node);
      return;
    }
    // Positional closure (e.g. `xs.forEach((x) {...})`) — higher-order
    // function call, introduces a visual nesting level for the reader.
    _enter();
    super.visitFunctionExpression(node);
    _exit();
  }
}
