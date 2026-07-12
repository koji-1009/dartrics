import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import '../metric.dart';

/// Cyclomatic Complexity (McCabe, 1976) — `1 + d` where `d` is the number of
/// linearly independent decision points in the control-flow graph.
///
/// In practice each of the following adds 1: `if`, `for`, `while`, `do`,
/// `switch case` (one per non-default arm — in a `switch` expression the
/// bare `_ =>` wildcard arm is the `default:` equivalent and is not
/// counted), `catch`, ternary `?:`, the short-circuit operators `&&` /
/// `||`, and the null-coalescing forms `??` / `??=` (each is the counted
/// ternary in disguise: `a ?? b` branches exactly like
/// `a != null ? a : b`). Nested closures are measured separately and do
/// **not** contribute to the enclosing function's value.
///
/// **Exhaustiveness discount:** when a `switch` statement or `switch`
/// expression dispatches over a value whose static type is a sealed
/// class or an enum, the case arms are **not** counted toward CC. The
/// Dart compiler enforces exhaustiveness on both kinds of subject, so
/// the reader carries no "did I forget a case?" cognitive burden — the
/// cases dispatch is closer to a typed if/else over a fixed-size domain
/// than to arbitrary branching. Counting them like ordinary `case` arms
/// over-reports CC on the modern Dart sealed-state and enum-dispatch
/// patterns. Detection requires resolution: the metric checks
/// `switch.expression.staticType.element` for a sealed `ClassElement`
/// or an `EnumElement`. On unresolved AST input (e.g. `parseString`
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
      '`while`, `do`, `case` arm, `catch`, ternary, `&&`, `||`, `??`, '
      '`??=`). The '
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

  /// Stack of "are we inside an exhaustive-dispatch switch right now"
  /// flags. The visitor pushes `true` on entry to a switch whose subject
  /// is a resolved sealed or enum type and pops on exit. Nested switches
  /// over exhaustive types (rare) handle the stack correctly.
  final List<bool> _insideExhaustiveSwitch = <bool>[];

  bool get _currentSwitchIsExhaustive =>
      _insideExhaustiveSwitch.isNotEmpty && _insideExhaustiveSwitch.last;

  // Skip nested closures: they are measured separately and don't add to
  // the enclosing function's value. `compute` accepts the function body
  // directly (a `FunctionBody`, never a `FunctionExpression`), so every
  // `FunctionExpression` reached here is a nested lambda — never recurse
  // into it.
  @override
  void visitFunctionExpression(FunctionExpression node) {}

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
    _insideExhaustiveSwitch.add(_isExhaustiveDispatch(node.expression));
    super.visitSwitchStatement(node);
    _insideExhaustiveSwitch.removeLast();
  }

  @override
  void visitSwitchExpression(SwitchExpression node) {
    _insideExhaustiveSwitch.add(_isExhaustiveDispatch(node.expression));
    super.visitSwitchExpression(node);
    _insideExhaustiveSwitch.removeLast();
  }

  @override
  void visitSwitchPatternCase(SwitchPatternCase node) {
    if (!_currentSwitchIsExhaustive) count++;
    super.visitSwitchPatternCase(node);
  }

  @override
  void visitSwitchExpressionCase(SwitchExpressionCase node) {
    if (!_currentSwitchIsExhaustive && !_isDefaultArm(node)) count++;
    super.visitSwitchExpressionCase(node);
  }

  /// A bare `_ =>` arm — untyped wildcard pattern, no `when` guard — is
  /// the switch expression's `default:` equivalent: the residual path,
  /// not a decision. It is skipped, mirroring how `default:` on a
  /// switch statement never counted. A typed wildcard (`int _ =>`) or a
  /// guarded one (`_ when c =>`) still narrows, so it still counts.
  static bool _isDefaultArm(SwitchExpressionCase node) {
    final guarded = node.guardedPattern;
    if (guarded.whenClause != null) return false;
    final pattern = guarded.pattern;
    return pattern is WildcardPattern && pattern.type == null;
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
    if (op == '&&' || op == '||' || op == '??') count++;
    super.visitBinaryExpression(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    // `a ??= b` is `a = a ?? b` — one decision point, like `??`.
    if (node.operator.lexeme == '??=') count++;
    super.visitAssignmentExpression(node);
  }

  /// Returns true when [subject] resolves to a sealed-class or enum
  /// type. The Dart compiler enforces exhaustiveness on switches over
  /// both, so the case arms aren't a "did I forget one?" cognitive
  /// load and shouldn't inflate CC. Falls through to `false` on
  /// unresolved AST input (no `staticType`).
  bool _isExhaustiveDispatch(Expression subject) {
    final type = subject.staticType;
    if (type == null) return false;
    final element = type.element;
    if (element is ClassElement) return element.isSealed;
    return element is EnumElement;
  }
}
