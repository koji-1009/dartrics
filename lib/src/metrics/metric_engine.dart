import 'dart:convert';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:crypto/crypto.dart';

import '../analyzer_runner.dart';
import '../config/config.dart';
import '../coverage/lcov_reader.dart';
import '../dismiss/dismissal.dart';
import '../dismiss/dismissal_index.dart';
import '../dismiss/dismissal_validator.dart';
import '../models/analysis_report.dart';
import '../models/source_location.dart';
import 'class/class_metric.dart';
import 'class/default_class_metrics.dart';
import 'flutter_aware.dart';
import 'function/default_function_metrics.dart';
import 'library/default_library_metrics.dart';
import 'library/library_metric.dart';
import 'metric.dart';
import 'test_aware.dart';

/// Runs the registered metric calculators against every resolved Dart
/// compilation unit produced by [AnalyzerRunner].
class MetricEngine {
  MetricEngine({
    List<FunctionMetric>? functionMetrics,
    List<ClassMetric>? classMetrics,
    List<LibraryMetric>? libraryMetrics,
    Map<String, MetricThresholds>? thresholds,
    this.flutter = true,
    this.test = true,
    this.coverage,
    DismissalIndex? dismissals,
    this.dismissalConfig = const DismissalConfig(),
    this.onDismissalRejection,
  }) : functionMetrics = functionMetrics ?? defaultFunctionMetrics,
       classMetrics = classMetrics ?? defaultClassMetrics,
       libraryMetrics = libraryMetrics ?? defaultLibraryMetrics,
       thresholds = thresholds ?? const {},
       dismissals = dismissals ?? DismissalIndex.empty();

  final List<FunctionMetric> functionMetrics;
  final List<ClassMetric> classMetrics;
  final List<LibraryMetric> libraryMetrics;
  final Map<String, MetricThresholds> thresholds;

  /// Mirror of [Config.flutter] — when `true`, [FlutterAware] skips
  /// metrics that produce noisy results on idiomatic Flutter widgets.
  final bool flutter;

  /// Mirror of [Config.test] — when `true`, [TestAware] relaxes the
  /// size-and-shape lenses on files under `test/` / `integration_test/`.
  final bool test;

  /// Optional lcov coverage data. When supplied, every emitted
  /// [MetricViolation] is annotated with the scope's line / branch
  /// coverage and a `complexityJustified` flag (see C2/C3 in
  /// `tmp/v0.1.0_round2_plan.md`).
  final CoverageIndex? coverage;

  /// Pre-built lookup for `// dartrics:dismiss` comments + the YAML
  /// sidecar. Defaults to an empty index — when no dismissals are
  /// present (or the user passed `--strict-dismiss`) the engine
  /// short-circuits the lookup with one map miss.
  final DismissalIndex dismissals;

  /// Validation knobs for matched dismissals. Mirrors the config and
  /// is consulted only when [dismissals] actually returns a hit.
  final DismissalConfig dismissalConfig;

  /// Optional sink for `requireReason` / `requireAuthor` / etc.
  /// rejections. The CLI wires this to a stderr writer so AI loops
  /// notice that their dismissals didn't take effect.
  final void Function(Dismissal dismissal, String reason)? onDismissalRejection;

  /// Metric ids whose `complexityJustified` tag is computed from
  /// coverage. Limited to CC and Cognitive because those are the
  /// metrics where high values can be earned by exhaustive testing.
  static const Set<String> _justifiableMetrics = {
    'cyclomatic-complexity',
    'cognitive-complexity',
  };

  /// Branch-coverage threshold above which a CC / Cognitive violation
  /// is considered "earned".
  static const double _branchJustifiedThreshold = 0.8;

  /// Line-coverage threshold used as a fallback when branch coverage
  /// data isn't available for the scope.
  static const double _lineJustifiedThreshold = 0.95;

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
    final lineCount = file.unit.lineInfo.lineCount;
    return MetricRecord(
      file: file.path,
      scope: ScopeRef(
        kind: ScopeKind.library,
        name: file.path,
        location: SourceLocation(path: file.path, line: 1, column: 1),
      ),
      values: values,
      violations: _violationsFor(
        values: values,
        path: file.path,
        scopeName: file.path,
        startLine: 1,
        endLine: lineCount,
      ),
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
    final isTestFile = test && TestAware.isTestPath(file.path);
    for (final decl in collector.declarations) {
      final input = FunctionMetricInput(context: ctx, declaration: decl);
      final skip = <String>{
        if (flutter) ...FlutterAware.skipsFor(decl),
        if (isTestFile) ...TestAware.functionSkips,
      };
      final values = <String, num>{};
      for (final calc in functionMetrics) {
        if (!_isMetricEnabled(calc.id, calc.defaultEnabled)) continue;
        if (skip.contains(calc.id)) continue;
        values[calc.id] = calc.compute(input);
      }
      final startLine = file.unit.lineInfo.getLocation(decl.offset).lineNumber;
      final endLine = file.unit.lineInfo.getLocation(decl.end).lineNumber;
      yield MetricRecord(
        file: file.path,
        scope: _scopeOf(decl, input, file.path),
        values: values,
        violations: _violationsFor(
          values: values,
          path: file.path,
          scopeName: input.scopeName,
          startLine: startLine,
          endLine: endLine,
        ),
      );
    }
  }

  bool _isMetricEnabled(String metricId, bool defaultEnabled) =>
      thresholds[metricId]?.enabled ?? defaultEnabled;

  Iterable<MetricRecord> _classRecordsFor(
    _ResolvedFile file,
    ClassIndex index,
  ) sync* {
    final isTestFile = test && TestAware.isTestPath(file.path);
    for (final cls in file.classes) {
      final input = ClassMetricInput(
        declaration: cls,
        lineInfo: file.unit.lineInfo,
        index: index,
      );
      final values = <String, num>{};
      for (final calc in classMetrics) {
        if (!_isMetricEnabled(calc.id, calc.defaultEnabled)) continue;
        if (isTestFile && TestAware.classSkips.contains(calc.id)) continue;
        values[calc.id] = calc.compute(input);
      }
      final loc = file.unit.lineInfo.getLocation(cls.offset);
      final endLine = file.unit.lineInfo.getLocation(cls.end).lineNumber;
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
        violations: _violationsFor(
          values: values,
          path: file.path,
          scopeName: input.className,
          startLine: loc.lineNumber,
          endLine: endLine,
        ),
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

  List<MetricViolation> _violationsFor({
    required Map<String, num> values,
    required String path,
    required String scopeName,
    required int startLine,
    required int endLine,
  }) {
    final cov = coverage?.forFile(path);
    final lineCoverage = cov?.lineCoverageInRange(startLine, endLine);
    final branchCoverage = cov?.branchCoverageInRange(startLine, endLine);
    final violations = <MetricViolation>[];
    for (final entry in values.entries) {
      final t = thresholds[entry.key];
      if (t == null) continue;
      final _Justification just = _justifiableMetrics.contains(entry.key)
          ? _classifyJustification(branch: branchCoverage, line: lineCoverage)
          : const _Justification.notApplicable();
      Severity? sev;
      num? thr;
      if (t.error != null && entry.value >= t.error!) {
        sev = Severity.error;
        thr = t.error!;
      } else if (t.warning != null && entry.value >= t.warning!) {
        sev = Severity.warning;
        thr = t.warning!;
      }
      if (sev == null || thr == null) continue;
      violations.add(
        _buildViolation(
          metricId: entry.key,
          severity: sev,
          threshold: thr,
          path: path,
          scopeName: scopeName,
          lineCoverage: lineCoverage,
          branchCoverage: branchCoverage,
          justification: just,
        ),
      );
    }
    return violations;
  }

  /// Builds a single violation, consulting [dismissals] for an entry
  /// that targets this exact `(file, scope, metric)`. Hits flow
  /// through [validateDismissal]; rejections become a
  /// `dismissalRejected` tag plus an `onDismissalRejection` callback.
  MetricViolation _buildViolation({
    required String metricId,
    required Severity severity,
    required num threshold,
    required String path,
    required String scopeName,
    required double? lineCoverage,
    required double? branchCoverage,
    required _Justification justification,
  }) {
    final id = computeViolationId(
      file: path,
      scope: scopeName,
      metricId: metricId,
    );
    final hit = dismissals.lookup(
      file: path,
      scope: scopeName,
      metricId: metricId,
    );
    if (hit == null) {
      return MetricViolation(
        id: id,
        metricId: metricId,
        severity: severity,
        threshold: threshold,
        scopeCoverage: lineCoverage,
        scopeBranchCoverage: branchCoverage,
        complexityJustified: justification.justified,
        complexityJustifiedBy: justification.by,
        complexityJustifiedThreshold: justification.threshold,
      );
    }
    final check = validateDismissal(hit, dismissalConfig);
    if (check is DismissalAccepted) {
      return MetricViolation(
        id: id,
        metricId: metricId,
        severity: severity,
        threshold: threshold,
        scopeCoverage: lineCoverage,
        scopeBranchCoverage: branchCoverage,
        complexityJustified: justification.justified,
        complexityJustifiedBy: justification.by,
        complexityJustifiedThreshold: justification.threshold,
        dismissed: true,
        dismissReason: hit.reason,
        dismissedBy: hit.by,
        dismissedAt: hit.at,
        dismissedFrom: hit.source,
      );
    }
    final rejected = check as DismissalRejected;
    onDismissalRejection?.call(rejected.dismissal, rejected.reason);
    return MetricViolation(
      id: id,
      metricId: metricId,
      severity: severity,
      threshold: threshold,
      scopeCoverage: lineCoverage,
      scopeBranchCoverage: branchCoverage,
      complexityJustified: justification.justified,
      complexityJustifiedBy: justification.by,
      complexityJustifiedThreshold: justification.threshold,
      dismissalRejected: rejected.reason,
    );
  }

  /// Decides which (if any) coverage rule justifies the violation.
  /// Branch coverage wins when present; line coverage is a more
  /// conservative fallback. Returns a `_Justification` carrying
  /// whether the violation is justified, which rule fired
  /// (`'branch'` / `'line'`), and the literal threshold the rule
  /// used. Reporters surface the decision so AI loops see the
  /// engine's basis instead of relying on documentation.
  _Justification _classifyJustification({
    required double? branch,
    required double? line,
  }) {
    if (branch != null) {
      return branch >= _branchJustifiedThreshold
          ? const _Justification(
              justified: true,
              by: 'branch',
              threshold: _branchJustifiedThreshold,
            )
          : const _Justification.notApplicable();
    }
    if (line != null) {
      return line >= _lineJustifiedThreshold
          ? const _Justification(
              justified: true,
              by: 'line',
              threshold: _lineJustifiedThreshold,
            )
          : const _Justification.notApplicable();
    }
    return const _Justification.notApplicable();
  }
}

/// Internal record carrying the justification decision plus the
/// metadata reporters surface alongside `complexityJustified`.
class _Justification {
  const _Justification({
    required this.justified,
    required this.by,
    required this.threshold,
  });

  const _Justification.notApplicable()
    : justified = false,
      by = null,
      threshold = null;

  final bool justified;
  final String? by;
  final double? threshold;
}

/// Stable id for a `(file, scope, metric)` triple, suitable for AI
/// loops to correlate violations across runs. The first 16 hex chars
/// of `sha256("<file>|<scope>|<metric>")` — 64 bits, well below the
/// birthday-collision floor for any single project.
///
/// Pipe-delimited (not colon) so absolute Windows paths (`C:/foo`) do
/// not introduce ambiguity.
String computeViolationId({
  required String file,
  required String scope,
  required String metricId,
}) {
  final digest = sha256.convert(utf8.encode('$file|$scope|$metricId'));
  return digest.toString().substring(0, 16);
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
