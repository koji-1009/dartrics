import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../metrics/flutter_aware.dart';
import '../../metrics/metric.dart';
import '../../metrics/test_aware.dart';
import '../lint_options.dart';

/// Internal helper that registers a [SimpleAstVisitor] for every
/// function-shaped declaration (functions, methods, constructors with
/// bodies) and runs a function-level [FunctionMetric] over each one.
///
/// Subclasses provide the metric calculator and the *default* threshold;
/// `registerNodeProcessors` resolves the *effective* threshold by reading
/// the `dartrics:` section of the project's `analysis_options.yaml` and
/// looking up the calculator's `id`. The visitor is then constructed with
/// that effective value so users can tighten or loosen each rule from
/// configuration without rebuilding the plugin.
abstract class FunctionMetricRule extends AnalysisRule {
  FunctionMetricRule({required super.name, required super.description});

  /// Calculator for the metric this rule reports on.
  FunctionMetric get metric;

  /// Threshold used when no override is present in `analysis_options.yaml`.
  /// Subclasses bake this as a `const`.
  num get defaultThreshold;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final options = LintOptions.load(context);
    final effective = options.thresholdFor(metric.id, defaultThreshold);
    final visitor = _Visitor(
      this,
      context,
      effective,
      options.flutter,
      options.test,
    );
    registry
      ..addFunctionDeclaration(this, visitor)
      ..addMethodDeclaration(this, visitor)
      ..addConstructorDeclaration(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context, this.threshold, this.flutter, this.test);

  final FunctionMetricRule rule;
  final RuleContext context;
  final num threshold;
  final bool flutter;
  final bool test;

  void _check(Declaration node) {
    final unit = context.currentUnit;
    if (unit == null) return;
    if (flutter && FlutterAware.skipsFor(node).contains(rule.metric.id)) {
      return;
    }
    if (test &&
        TestAware.functionSkips.contains(rule.metric.id) &&
        TestAware.isTestPath(unit.file.path)) {
      return;
    }
    final input = FunctionMetricInput(
      context: (
        unit: unit.unit,
        source: unit.content,
        lineInfo: unit.unit.lineInfo,
      ),
      declaration: node,
    );
    final value = rule.metric.compute(input);
    if (value < threshold) return;
    rule.reportAtNode(node, arguments: [value, threshold]);
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
