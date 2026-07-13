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
  /// coverage and a `complexityJustified` flag.
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
    for (final entry in units) {
      final classCollector = _ClassCollector();
      entry.unit.unit.accept(classCollector);
      resolved.add(
        _ResolvedFile(
          path: entry.path,
          unit: entry.unit,
          classes: classCollector.classes,
        ),
      );
    }
    final libraryIndex = LibraryIndex.build([
      for (final f in resolved) (path: f.path, unit: f.unit),
    ]);

    final records = <MetricRecord>[];
    for (final file in resolved) {
      records.addAll(_functionRecordsFor(file));
      records.addAll(_classRecordsFor(file));
      records.add(_libraryRecordFor(file, libraryIndex));
    }
    return records;
  }

  /// One [ExplainEntry] per metric that fired at least one violation
  /// in [records]. Iterates the calculator set this engine was
  /// constructed with and filters by fired metric ids — the lookup is
  /// total over that set, so no nullable indirection (and no bang)
  /// appears at the call site. Output is in calculator declaration
  /// order: function metrics, then class metrics, then library
  /// metrics. AI consumers index the block by `metricId`, not by
  /// position, so the order is informational rather than load-bearing.
  List<ExplainEntry> firedExplanations(List<MetricRecord> records) {
    final firedIds = <String>{
      for (final r in records)
        for (final v in r.violations) v.metricId,
    };
    if (firedIds.isEmpty) return const [];
    final out = <ExplainEntry>[];
    for (final m in functionMetrics) {
      if (firedIds.contains(m.id)) {
        out.add(
          ExplainEntry(
            metricId: m.id,
            rationale: m.rationale,
            refactorHints: m.refactorHints,
            references: m.references,
          ),
        );
      }
    }
    for (final m in classMetrics) {
      if (firedIds.contains(m.id)) {
        out.add(
          ExplainEntry(
            metricId: m.id,
            rationale: m.rationale,
            refactorHints: m.refactorHints,
            references: m.references,
          ),
        );
      }
    }
    for (final m in libraryMetrics) {
      if (firedIds.contains(m.id)) {
        out.add(
          ExplainEntry(
            metricId: m.id,
            rationale: m.rationale,
            refactorHints: m.refactorHints,
            references: m.references,
          ),
        );
      }
    }
    return out;
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
        kind: .library,
        name: file.path,
        location: SourceLocation(path: file.path, line: 1, column: 1),
        endLine: lineCount,
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
      final input = FunctionMetricInput(
        context: ctx,
        declaration: decl,
        isTestFile: isTestFile,
      );
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
        scope: _scopeOf(decl, input, file.path, endLine: endLine),
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

  Iterable<MetricRecord> _classRecordsFor(_ResolvedFile file) sync* {
    final isTestFile = test && TestAware.isTestPath(file.path);
    for (final cls in file.classes) {
      final input = ClassMetricInput(
        declaration: cls,
        lineInfo: file.unit.lineInfo,
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
          kind: .klass,
          name: input.className,
          location: SourceLocation(
            path: file.path,
            line: loc.lineNumber,
            column: loc.columnNumber,
          ),
          endLine: endLine,
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

  ScopeRef _scopeOf(
    AstNode decl,
    FunctionMetricInput input,
    String path, {
    required int endLine,
  }) {
    final loc = input.lineInfo.getLocation(decl.offset);
    final source = SourceLocation(
      path: path,
      line: loc.lineNumber,
      column: loc.columnNumber,
    );
    final ScopeKind kind;
    if (decl is FunctionDeclaration) {
      kind = .function;
    } else if (decl is FunctionExpression) {
      kind = .closure;
    } else {
      kind = .method;
    }
    return ScopeRef(
      kind: kind,
      name: input.scopeName,
      location: source,
      endLine: endLine,
    );
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
      final triggered = _classifyThreshold(entry.value, t);
      if (triggered == null) continue;
      violations.add(
        _buildViolation(
          metricId: entry.key,
          severity: triggered.severity,
          threshold: triggered.threshold,
          path: path,
          scopeName: scopeName,
          lineCoverage: lineCoverage,
          branchCoverage: branchCoverage,
          justification: _justificationFor(
            entry.key,
            branchCoverage: branchCoverage,
            lineCoverage: lineCoverage,
          ),
        ),
      );
    }
    return violations;
  }

  /// Returns the (severity, threshold) pair that fired for [value]
  /// against [t], preferring `error` over `warning`. `null` when the
  /// value sits below both bands or the corresponding threshold is
  /// unset.
  ({Severity severity, num threshold})? _classifyThreshold(
    num value,
    MetricThresholds t,
  ) {
    if (t.error != null && value >= t.error!) {
      return (severity: .error, threshold: t.error!);
    }
    if (t.warning != null && value >= t.warning!) {
      return (severity: .warning, threshold: t.warning!);
    }
    return null;
  }

  _Justification _justificationFor(
    String metricId, {
    required double? branchCoverage,
    required double? lineCoverage,
  }) {
    if (!_justifiableMetrics.contains(metricId)) {
      return const _Justification.notApplicable();
    }
    return _classifyJustification(branch: branchCoverage, line: lineCoverage);
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
    switch (check) {
      case DismissalAccepted():
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
      case DismissalRejected(:final dismissal, :final reason):
        onDismissalRejection?.call(dismissal, reason);
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
          dismissalRejected: reason,
        );
    }
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
  final declarations = <AstNode>[];

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

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // A literal that is the body of a named declaration is already
    // covered by the wrapping FunctionDeclaration record; every other
    // literal is a closure and gets its own record, consistent with how
    // local named functions are measured apart from their enclosing
    // function.
    if (node.parent is! FunctionDeclaration) {
      declarations.add(node);
    }
    super.visitFunctionExpression(node);
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
