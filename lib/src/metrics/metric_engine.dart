import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../analyzer_runner.dart';
import '../config/config.dart';
import '../models/analysis_report.dart';
import '../models/source_location.dart';
import 'function/_default_function_metrics.dart';
import 'metric.dart';

/// Runs the registered function-level metric calculators against every
/// resolved Dart compilation unit produced by [AnalyzerRunner].
class MetricEngine {
  MetricEngine({
    List<FunctionMetric>? functionMetrics,
    Map<String, MetricThresholds>? thresholds,
  })  : functionMetrics = functionMetrics ?? defaultFunctionMetrics,
        thresholds = thresholds ?? const {};

  final List<FunctionMetric> functionMetrics;
  final Map<String, MetricThresholds> thresholds;

  Future<List<MetricRecord>> analyze(AnalyzerRunner runner) async {
    final files = await runner.collectDartFiles();
    final records = <MetricRecord>[];
    for (final path in files) {
      final unit = await runner.resolve(path);
      if (unit == null) continue;
      final collector = _FunctionCollector();
      unit.unit.accept(collector);
      for (final decl in collector.declarations) {
        final input = FunctionMetricInput(
          unit: unit.unit,
          source: unit.content,
          lineInfo: unit.lineInfo,
          declaration: decl,
        );
        final values = <String, num>{};
        for (final calc in functionMetrics) {
          values[calc.id] = calc.compute(input);
        }
        records.add(MetricRecord(
          file: path,
          scope: _scopeOf(decl, input, path),
          values: values,
          violations: _violationsFor(values),
        ));
      }
    }
    return records;
  }

  ScopeRef _scopeOf(Declaration decl, FunctionMetricInput input, String path) {
    final loc = input.lineInfo.getLocation(decl.offset);
    final source = SourceLocation(
      path: path,
      line: loc.lineNumber,
      column: loc.columnNumber,
    );
    final ScopeKind kind;
    if (decl is FunctionDeclaration) {
      kind = ScopeKind.function;
    } else if (decl is MethodDeclaration) {
      kind = ScopeKind.method;
    } else if (decl is ConstructorDeclaration) {
      kind = ScopeKind.method;
    } else {
      kind = ScopeKind.function;
    }
    return ScopeRef(kind: kind, name: input.scopeName, location: source);
  }

  List<MetricViolation> _violationsFor(Map<String, num> values) {
    final violations = <MetricViolation>[];
    for (final entry in values.entries) {
      final t = thresholds[entry.key];
      if (t == null) continue;
      if (t.error != null && entry.value >= t.error!) {
        violations.add(MetricViolation(
          metricId: entry.key,
          severity: Severity.error,
          threshold: t.error!,
        ));
      } else if (t.warning != null && entry.value >= t.warning!) {
        violations.add(MetricViolation(
          metricId: entry.key,
          severity: Severity.warning,
          threshold: t.warning!,
        ));
      }
    }
    return violations;
  }
}

class _FunctionCollector extends RecursiveAstVisitor<void> {
  final declarations = <Declaration>[];

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    declarations.add(node);
    // Don't descend — local function declarations inside the body are
    // captured via their own `FunctionDeclarationStatement` traversal.
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.body is! EmptyFunctionBody) {
      declarations.add(node);
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    if (node.body is! EmptyFunctionBody) {
      declarations.add(node);
    }
    super.visitConstructorDeclaration(node);
  }
}
