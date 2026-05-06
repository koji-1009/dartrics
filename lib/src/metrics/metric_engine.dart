import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../analyzer_runner.dart';
import '../config/config.dart';
import '../models/analysis_report.dart';
import '../models/source_location.dart';
import 'class/class_metric.dart';
import 'class/default_class_metrics.dart';
import 'function/default_function_metrics.dart';
import 'library/default_library_metrics.dart';
import 'library/library_metric.dart';
import 'metric.dart';

/// Runs the registered metric calculators against every resolved Dart
/// compilation unit produced by [AnalyzerRunner].
class MetricEngine {
  MetricEngine({
    List<FunctionMetric>? functionMetrics,
    List<ClassMetric>? classMetrics,
    List<LibraryMetric>? libraryMetrics,
    Map<String, MetricThresholds>? thresholds,
  }) : functionMetrics = functionMetrics ?? defaultFunctionMetrics,
       classMetrics = classMetrics ?? defaultClassMetrics,
       libraryMetrics = libraryMetrics ?? defaultLibraryMetrics,
       thresholds = thresholds ?? const {};

  final List<FunctionMetric> functionMetrics;
  final List<ClassMetric> classMetrics;
  final List<LibraryMetric> libraryMetrics;
  final Map<String, MetricThresholds> thresholds;

  Future<List<MetricRecord>> analyze(AnalyzerRunner runner) async {
    final units = await runner.resolveAll();
    return analyzeResolved(units);
  }

  /// Variant of [analyze] that operates on already-resolved compilation
  /// units. Lets callers (e.g. the CLI flow that also runs the unused
  /// detector) share resolution work.
  List<MetricRecord> analyzeResolved(
    List<({String path, ResolvedUnitResult unit})> units,
  ) {
    final resolved = <_ResolvedFile>[];
    final allClasses = <ClassDeclaration>[];
    for (final entry in units) {
      final classCollector = _ClassCollector();
      entry.unit.unit.accept(classCollector);
      allClasses.addAll(classCollector.classes);
      resolved.add(
        _ResolvedFile(
          path: entry.path,
          unit: entry.unit,
          classes: classCollector.classes,
        ),
      );
    }
    final classIndex = ClassIndex.build(allClasses);
    final libraryIndex = LibraryIndex.build([
      for (final f in resolved) (path: f.path, unit: f.unit),
    ]);

    final records = <MetricRecord>[];
    for (final file in resolved) {
      records.addAll(_functionRecordsFor(file));
      records.addAll(_classRecordsFor(file, classIndex));
      records.add(_libraryRecordFor(file, libraryIndex));
    }
    return records;
  }

  MetricRecord _libraryRecordFor(_ResolvedFile file, LibraryIndex index) {
    final input = LibraryMetricInput(path: file.path, index: index);
    final values = <String, num>{};
    for (final calc in libraryMetrics) {
      if (!_isMetricEnabled(calc.id, calc.defaultEnabled)) continue;
      values[calc.id] = calc.compute(input);
    }
    return MetricRecord(
      file: file.path,
      scope: ScopeRef(
        kind: ScopeKind.library,
        name: file.path,
        location: SourceLocation(path: file.path, line: 1, column: 1),
      ),
      values: values,
      violations: _violationsFor(values),
    );
  }

  Iterable<MetricRecord> _functionRecordsFor(_ResolvedFile file) sync* {
    final collector = _FunctionCollector();
    file.unit.unit.accept(collector);
    final ctx = (
      unit: file.unit.unit,
      source: file.unit.content,
      lineInfo: file.unit.lineInfo,
    );
    for (final decl in collector.declarations) {
      final input = FunctionMetricInput(context: ctx, declaration: decl);
      final values = <String, num>{};
      for (final calc in functionMetrics) {
        if (!_isMetricEnabled(calc.id, calc.defaultEnabled)) continue;
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

  bool _isMetricEnabled(String metricId, bool defaultEnabled) =>
      thresholds[metricId]?.enabled ?? defaultEnabled;

  Iterable<MetricRecord> _classRecordsFor(
    _ResolvedFile file,
    ClassIndex index,
  ) sync* {
    for (final cls in file.classes) {
      final input = ClassMetricInput(
        declaration: cls,
        lineInfo: file.unit.lineInfo,
        index: index,
      );
      final values = <String, num>{};
      for (final calc in classMetrics) {
        if (!_isMetricEnabled(calc.id, calc.defaultEnabled)) continue;
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
        violations.add(
          MetricViolation(
            metricId: entry.key,
            severity: Severity.error,
            threshold: t.error!,
          ),
        );
      } else if (t.warning != null && entry.value >= t.warning!) {
        violations.add(
          MetricViolation(
            metricId: entry.key,
            severity: Severity.warning,
            threshold: t.warning!,
          ),
        );
      }
    }
    return violations;
  }
}

class _ResolvedFile {
  _ResolvedFile({
    required this.path,
    required this.unit,
    required this.classes,
  });
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
