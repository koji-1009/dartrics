import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../analyzer_runner.dart';
import '../config/config.dart';
import '../models/analysis_report.dart';
import '../models/source_location.dart';
import 'class/_default_class_metrics.dart';
import 'class/class_metric.dart';
import 'function/_default_function_metrics.dart';
import 'metric.dart';

/// Runs the registered metric calculators against every resolved Dart
/// compilation unit produced by [AnalyzerRunner].
class MetricEngine {
  MetricEngine({
    List<FunctionMetric>? functionMetrics,
    List<ClassMetric>? classMetrics,
    Map<String, MetricThresholds>? thresholds,
  })  : functionMetrics = functionMetrics ?? defaultFunctionMetrics,
        classMetrics = classMetrics ?? defaultClassMetrics,
        thresholds = thresholds ?? const {};

  final List<FunctionMetric> functionMetrics;
  final List<ClassMetric> classMetrics;
  final Map<String, MetricThresholds> thresholds;

  Future<List<MetricRecord>> analyze(AnalyzerRunner runner) async {
    final files = await runner.collectDartFiles();

    // First pass: resolve every compilation unit and collect class
    // declarations across the project so DIT/NOC have a global view.
    final resolved = <_ResolvedFile>[];
    final allClasses = <ClassDeclaration>[];
    for (final path in files) {
      final unit = await runner.resolve(path);
      if (unit == null) continue;
      final classCollector = _ClassCollector();
      unit.unit.accept(classCollector);
      allClasses.addAll(classCollector.classes);
      resolved.add(_ResolvedFile(path: path, unit: unit, classes: classCollector.classes));
    }
    final classIndex = ClassIndex.build(allClasses);

    final records = <MetricRecord>[];
    for (final file in resolved) {
      records.addAll(_functionRecordsFor(file));
      records.addAll(_classRecordsFor(file, classIndex));
    }
    return records;
  }

  Iterable<MetricRecord> _functionRecordsFor(_ResolvedFile file) sync* {
    final collector = _FunctionCollector();
    file.unit.unit.accept(collector);
    for (final decl in collector.declarations) {
      final input = FunctionMetricInput(
        unit: file.unit.unit,
        source: file.unit.content,
        lineInfo: file.unit.lineInfo,
        declaration: decl,
      );
      final values = <String, num>{};
      for (final calc in functionMetrics) {
        values[calc.id] = calc.compute(input);
      }
      yield MetricRecord(
        file: file.path,
        scope: _scopeOf(decl, input, file.path),
        values: values,
        violations: _violationsFor(values),
      );
    }
  }

  Iterable<MetricRecord> _classRecordsFor(_ResolvedFile file, ClassIndex index) sync* {
    for (final cls in file.classes) {
      final input = ClassMetricInput(
        declaration: cls,
        lineInfo: file.unit.lineInfo,
        index: index,
      );
      final values = <String, num>{};
      for (final calc in classMetrics) {
        values[calc.id] = calc.compute(input);
      }
      final loc = file.unit.lineInfo.getLocation(cls.offset);
      yield MetricRecord(
        file: file.path,
        scope: ScopeRef(
          kind: ScopeKind.klass,
          name: input.className,
          location: SourceLocation(
            path: file.path,
            line: loc.lineNumber,
            column: loc.columnNumber,
          ),
        ),
        values: values,
        violations: _violationsFor(values),
      );
    }
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
    } else {
      kind = ScopeKind.method;
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

class _ResolvedFile {
  _ResolvedFile({required this.path, required this.unit, required this.classes});
  final String path;
  final ResolvedUnitResult unit;
  final List<ClassDeclaration> classes;
}

class _FunctionCollector extends RecursiveAstVisitor<void> {
  final declarations = <Declaration>[];

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    declarations.add(node);
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

class _ClassCollector extends RecursiveAstVisitor<void> {
  final classes = <ClassDeclaration>[];

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    classes.add(node);
    super.visitClassDeclaration(node);
  }
}
