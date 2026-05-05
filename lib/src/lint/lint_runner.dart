import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import '../metrics/function/cognitive_complexity.dart';
import '../metrics/function/cyclomatic_complexity.dart';
import '../metrics/function/max_nesting_level.dart';
import '../metrics/function/number_of_parameters.dart';
import '../metrics/metric.dart';
import 'lint_config.dart';
import 'lint_diagnostic.dart';

/// Runs every enabled lightweight metric over [unit] and returns the
/// diagnostics produced by threshold violations. Both the CLI plugin
/// entrypoint and standalone embedders go through this function.
List<DartricsDiagnostic> diagnose({
  required CompilationUnit unit,
  required LineInfo lineInfo,
  required String path,
  required String source,
  DartricsLintConfig config = const DartricsLintConfig(),
}) {
  final out = <DartricsDiagnostic>[];
  final visitor = _DeclVisitor((decl) {
    final input = FunctionMetricInput.fromDeclaration(
      unit: unit,
      source: source,
      lineInfo: lineInfo,
      declaration: decl,
    );
    void check<M extends FunctionMetric>(M metric, RuleConfig rc) {
      if (!rc.enabled) return;
      final value = metric.compute(input);
      final severity = _severityFor(value, rc);
      if (severity == null) return;
      final loc = lineInfo.getLocation(decl.offset);
      final scopeLength = decl.length;
      out.add(
        DartricsDiagnostic(
          ruleId: metric.id,
          severity: severity,
          message:
              '${metric.id} = $value '
              'exceeds the ${severity.name} threshold (${_thresholdOf(severity, rc)})',
          path: path,
          line: loc.lineNumber,
          column: loc.columnNumber,
          length: scopeLength,
        ),
      );
    }

    check(const CyclomaticComplexity(), config.cyclomaticComplexity);
    check(const CognitiveComplexity(), config.cognitiveComplexity);
    check(const MaxNestingLevel(), config.maxNestingLevel);
    check(const NumberOfParameters(), config.numberOfParameters);
  });
  unit.accept(visitor);
  return out;
}

DiagnosticSeverity? _severityFor(num value, RuleConfig rc) {
  if (rc.error != null && value >= rc.error!) {
    return DiagnosticSeverity.error;
  }
  if (rc.warning != null && value >= rc.warning!) {
    return DiagnosticSeverity.warning;
  }
  return null;
}

num _thresholdOf(DiagnosticSeverity severity, RuleConfig rc) {
  switch (severity) {
    case DiagnosticSeverity.error:
      return rc.error ?? rc.warning ?? 0;
    case DiagnosticSeverity.warning:
      return rc.warning ?? 0;
  }
}

class _DeclVisitor extends RecursiveAstVisitor<void> {
  _DeclVisitor(this.onEach);
  final void Function(Declaration) onEach;

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    onEach(node);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.body is! EmptyFunctionBody) onEach(node);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    if (node.body is! EmptyFunctionBody) onEach(node);
    super.visitConstructorDeclaration(node);
  }
}
