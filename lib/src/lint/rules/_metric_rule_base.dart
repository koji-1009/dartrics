import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../metrics/metric.dart';

/// Internal helper that registers a [SimpleAstVisitor] for every
/// function-shaped declaration (functions, methods, constructors with bodies)
/// and runs a function-level [FunctionMetric] over each one.
///
/// Subclasses provide the metric calculator and the threshold; when a
/// declaration's value reaches the threshold, [reportAtNode] is invoked with
/// `[value, threshold]` so the rule's `LintCode.problemMessage` can interpolate
/// them via `{0}` / `{1}`.
abstract class FunctionMetricRule extends AnalysisRule {
  FunctionMetricRule({required super.name, required super.description});

  /// Calculator for the metric this rule reports on.
  FunctionMetric get metric;

  /// Threshold the metric value is compared against. The rule reports when
  /// `value >= threshold`.
  num get threshold;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry
      ..addFunctionDeclaration(this, visitor)
      ..addMethodDeclaration(this, visitor)
      ..addConstructorDeclaration(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final FunctionMetricRule rule;
  final RuleContext context;

  void _check(Declaration node) {
    final unit = context.currentUnit;
    if (unit == null) return;
    final input = FunctionMetricInput.fromDeclaration(
      unit: unit.unit,
      source: unit.content,
      lineInfo: unit.unit.lineInfo,
      declaration: node,
    );
    final value = rule.metric.compute(input);
    if (value < rule.threshold) return;
    rule.reportAtNode(node, arguments: [value, rule.threshold]);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) => _check(node);

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.body is EmptyFunctionBody) return;
    _check(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    if (node.body is EmptyFunctionBody) return;
    _check(node);
  }
}
