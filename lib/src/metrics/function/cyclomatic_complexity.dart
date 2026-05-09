import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import '../metric.dart';

/// Cyclomatic Complexity (McCabe, 1976) — `1 + d` where `d` is the number of
/// linearly independent decision points in the control-flow graph.
///
/// In practice each of the following adds 1: `if`, `for`, `while`, `do`,
/// `switch case` (one per non-default arm), `catch`, ternary `?:`, and the
/// short-circuit operators `&&` / `||`. Nested closures are measured
/// separately and do **not** contribute to the enclosing function's value.
///
/// **Sealed-aware discount:** when a `switch` or `switch` expression
/// dispatches over a value whose static type is a sealed class, the
/// case arms are **not** counted toward CC. The Dart compiler enforces
/// exhaustiveness on sealed-typed subjects, so the reader carries no
/// "did I forget a case?" cognitive burden — the cases dispatch is
/// closer to a typed if/else over a fixed-size domain than to arbitrary
/// branching. Counting them like ordinary `case` arms over-reports CC
/// on the modern Dart sealed-state pattern. Detection requires
/// resolution: the metric checks `switch.expression.staticType.element`
/// for the `isSealed` flag. On unresolved AST input (e.g. `parseString`
/// in tests) the static type is `null` and the discount falls back to
/// the original "every case adds 1" rule.
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
  List<String> get references => const [
    'McCabe, T. J. (1976). A Complexity Measure. IEEE Transactions on Software Engineering, SE-2(4), 308–320.',
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

  /// Stack of "are we inside a sealed-dispatch switch right now" flags.
  /// The visitor pushes `true` on entry to a switch whose subject is a
  /// resolved sealed type and pops on exit. Nested switches over
  /// sealed types (rare) handle the stack correctly.
  final List<bool> _insideSealedSwitch = <bool>[];

  bool get _currentSwitchIsSealed =>
      _insideSealedSwitch.isNotEmpty && _insideSealedSwitch.last;

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
  void visitSwitchStatement(SwitchStatement node) {
    _insideSealedSwitch.add(_isSealedDispatch(node.expression));
    super.visitSwitchStatement(node);
    _insideSealedSwitch.removeLast();
  }

  @override
  void visitSwitchExpression(SwitchExpression node) {
    _insideSealedSwitch.add(_isSealedDispatch(node.expression));
    super.visitSwitchExpression(node);
    _insideSealedSwitch.removeLast();
  }

  @override
  void visitSwitchPatternCase(SwitchPatternCase node) {
    if (!_currentSwitchIsSealed) count++;
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

  /// Returns true when [subject] resolves to a sealed-class type. The
  /// Dart compiler enforces exhaustiveness on switches over sealed
  /// types, so the case arms aren't a "did I forget one?" cognitive
  /// load and shouldn't inflate CC. Falls through to `false` on
  /// unresolved AST input (no `staticType`).
  bool _isSealedDispatch(Expression subject) {
    final type = subject.staticType;
    if (type == null) return false;
    final element = type.element;
    if (element is ClassElement) return element.isSealed;
    return false;
  }
}
