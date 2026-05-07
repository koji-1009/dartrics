import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../metric.dart';

/// Maximum depth of nested constructor calls — designed to surface
/// "deep Widget tree" code shapes inside `Widget.build()` and inside
/// builder callbacks (`ListView.builder`'s `itemBuilder`, `Builder`,
/// `LayoutBuilder`, …).
///
/// This is the Flutter-specific complement to `maximum-nesting-level`:
/// max-nesting-level captures *control-flow* depth (`if` / `for` /
/// `while` / `switch` / closure bodies), and produces 0 on a healthy
/// Widget tree because no control-flow construct is involved.
/// `widget-tree-depth` captures the **visual** depth that a reader sees
/// when they trace a `Container(child: Container(child: ...))` chain.
///
/// Counting rule: each `InstanceCreationExpression` (= `Foo(...)` or
/// `const Foo(...)` syntax) on the path from a leaf up to the root of
/// the body adds one level. Method-call chains (`.copyWith()`,
/// `.then(...)`) and identifier expressions are not counted; only
/// constructor calls. The rule is intentionally syntactic — no element
/// resolution, no assumption that the `Foo` is from `package:flutter` —
/// so the metric is also informative on non-Flutter Dart code that
/// builds nested data records via deep constructor literals.
///
/// Defaults: warning at depth 7, off-by-default. Flutter authors who
/// want this signal opt in via
/// `dartrics: { metrics: { widget-tree-depth: { enabled: true } } }`.
/// On non-Flutter Dart this metric will rarely fire because nested
/// constructor literals are uncommon outside Widget trees; non-Flutter
/// projects can either leave it off (saving the visitor cost) or turn
/// it on for free signal on builder-pattern code.
class WidgetTreeDepth extends FunctionMetric {
  const WidgetTreeDepth();

  @override
  String get id => 'widget-tree-depth';

  /// Off by default — the metric is most useful in Flutter projects
  /// where chained `Container(child: ...)` patterns appear, and would
  /// otherwise sit silent in pure-Dart projects. Opt in to fire it.
  @override
  bool get defaultEnabled => false;

  @override
  String get rationale =>
      'Widget tree depth counts the deepest chain of nested constructor '
      'calls inside the function body. In Flutter, this is the visual '
      'depth a reader sees walking a `Container(child: Container(...))` '
      'tree — the same shape `maximum-nesting-level` cannot detect '
      'because no control-flow construct is involved. Flutter community '
      'practice is to extract a sub-widget once a build tree exceeds '
      '~5–7 levels: deeper trees are harder to scan and tend to '
      're-render more aggressively. The metric is also informative on '
      'non-Flutter Dart code that builds deeply-nested constructor '
      'records (e.g. JSON shape literals).';

  @override
  List<String> get refactorHints => const [
    'Extract the deepest sub-tree into a private `_buildXxx()` helper or a separate small Widget class.',
    'Replace `Padding(child: Padding(child: ...))` chains with a single `Padding(padding: EdgeInsets.symmetric(...))`.',
    'Use a named helper or a `const` widget when the same sub-tree appears more than once.',
    'Lift state up so a deep `Builder(builder: ...)` callback isn\'t needed inside the tree.',
  ];

  @override
  num compute(FunctionMetricInput input) {
    final visitor = _DepthVisitor();
    input.body.accept(visitor);
    return visitor.maxDepth;
  }
}

/// Tracks the deepest `InstanceCreationExpression` chain on any path
/// through the body. Plain method calls and field accesses are
/// transparent to the depth counter; only constructor invocations
/// (`Foo(...)` / `const Foo(...)`) increment.
class _DepthVisitor extends RecursiveAstVisitor<void> {
  int currentDepth = 0;
  int maxDepth = 0;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    currentDepth++;
    if (currentDepth > maxDepth) maxDepth = currentDepth;
    super.visitInstanceCreationExpression(node);
    currentDepth--;
  }
}
