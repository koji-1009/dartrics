import '../dismiss/dismissal.dart';
import 'source_location.dart';
import 'unused_declaration.dart';

/// Severity level attached to a metric violation.
///
/// Ordered so `value` comparisons answer "is at least this severe?".
enum Severity {
  info(0),
  warning(1),
  error(2);

  const Severity(this.rank);
  final int rank;
}

/// What kind of program element a metric describes.
enum ScopeKind { function, method, klass, file, library }

class ScopeRef {
  const ScopeRef({
    required this.kind,
    required this.name,
    required this.location,
  });

  final ScopeKind kind;
  final String name;
  final SourceLocation location;

  Map<String, Object?> toJson() => {
    'type': kind.name,
    'name': name,
    'line': location.line,
  };
}

class MetricViolation {
  const MetricViolation({
    required this.metricId,
    required this.severity,
    required this.threshold,
    this.scopeCoverage,
    this.scopeBranchCoverage,
    this.complexityJustified = false,
    this.dismissed = false,
    this.dismissReason,
    this.dismissedBy,
    this.dismissedAt,
    this.dismissedFrom,
    this.dismissalRejected,
  });

  final String metricId;
  final Severity severity;
  final num threshold;

  /// Line coverage of the violating scope, in `[0.0, 1.0]`. `null` when
  /// no `lcov.info` was supplied or when the scope had no executable
  /// lines reported.
  final double? scopeCoverage;

  /// Branch coverage of the violating scope, in `[0.0, 1.0]`. `null`
  /// when the lcov source contained no `BRDA:` records for the range.
  final double? scopeBranchCoverage;

  /// True when the violating scope is heavily covered enough that its
  /// complexity is most likely "earned" rather than incidental. Set by
  /// the engine when `branch >= 0.8` (or `line >= 0.95` when no branch
  /// data is available) on the CC / Cognitive metrics. AI loops should
  /// deprioritise refactoring these.
  final bool complexityJustified;

  /// True when a `dartrics:dismiss` entry — comment or YAML — matched
  /// this violation and passed the configured validation rules. The
  /// violation still appears in the report (so audits can review what
  /// was suppressed); it is just deprioritised by the AI reporter and
  /// tagged in the human-facing reporters.
  final bool dismissed;

  /// Rationale carried in from the matched dismissal. Empty string when
  /// the project disabled `requireReason` and the entry omitted one.
  /// `null` when [dismissed] is false.
  final String? dismissReason;

  /// Author tag from a YAML dismissal's `by:`. Only ever populated
  /// when [dismissedFrom] is [DismissalSource.yaml].
  final String? dismissedBy;

  /// Timestamp from a YAML dismissal's `at:`. Only ever populated
  /// when [dismissedFrom] is [DismissalSource.yaml].
  final DateTime? dismissedAt;

  /// Which channel the accepted dismissal was sourced from.
  final DismissalSource? dismissedFrom;

  /// Set when a dismissal entry matched this violation but failed
  /// validation (e.g. reason too short). The violation stays live;
  /// AI loops should read this and amend the dismissal. Mutually
  /// exclusive with [dismissed].
  final String? dismissalRejected;

  Map<String, Object?> toJson() => {
    'metric': metricId,
    'level': severity.name,
    'threshold': threshold,
    if (scopeCoverage != null) 'scopeCoverage': scopeCoverage,
    if (scopeBranchCoverage != null) 'scopeBranchCoverage': scopeBranchCoverage,
    if (complexityJustified) 'complexityJustified': true,
    if (dismissed) 'dismissed': true,
    if (dismissReason != null) 'dismissReason': dismissReason,
    if (dismissedBy != null) 'dismissedBy': dismissedBy,
    if (dismissedAt != null) 'dismissedAt': dismissedAt!.toIso8601String(),
    if (dismissedFrom != null) 'dismissedFrom': dismissedFrom!.name,
    if (dismissalRejected != null) 'dismissalRejected': dismissalRejected,
  };
}

/// Per-scope bundle of metric values and violations.
class MetricRecord {
  const MetricRecord({
    required this.file,
    required this.scope,
    required this.values,
    required this.violations,
  });

  final String file;
  final ScopeRef scope;
  final Map<String, num> values;
  final List<MetricViolation> violations;

  Severity? get worstSeverity {
    Severity? worst;
    for (final v in violations) {
      if (worst == null || v.severity.rank > worst.rank) worst = v.severity;
    }
    return worst;
  }

  Map<String, Object?> toJson() => {
    'file': file,
    'scope': scope.toJson(),
    'values': values,
    'violations': violations.map((v) => v.toJson()).toList(),
  };
}

/// Per-file fingerprint persisted into the snapshot file. The hash is
/// keyed off the raw source bytes, deliberately ignoring `mtime` so that
/// VCS / CI clones with a fresh stamp don't blow the cache.
class AnalyzedFile {
  const AnalyzedFile({required this.path, required this.sha256});

  factory AnalyzedFile.fromJson(Map<String, Object?> json) => AnalyzedFile(
    path: json['path']! as String,
    sha256: json['sha256']! as String,
  );

  final String path;
  final String sha256;

  Map<String, Object?> toJson() => {'path': path, 'sha256': sha256};
}

/// Catalogue entry for a metric whose rationale should accompany the
/// emitted report (`--explain <metric-id>`).
class ExplainEntry {
  const ExplainEntry({
    required this.metricId,
    required this.rationale,
    required this.refactorHints,
  });

  final String metricId;
  final String rationale;
  final List<String> refactorHints;
}

/// Top-level result returned by the analyzer.
class AnalysisReport {
  AnalysisReport({
    required this.version,
    required this.metrics,
    required this.unused,
    this.analyzedFiles = const [],
    this.explanations = const [],
  });

  final String version;
  final List<MetricRecord> metrics;
  final List<UnusedDeclaration> unused;

  /// Optional snapshot of every file the analyzer hashed during this run.
  /// Empty when snapshot mode is `none` or the snapshot writer isn't
  /// engaged. Only the JSON reporter persists this field.
  final List<AnalyzedFile> analyzedFiles;

  /// Optional list of rationale + hint blurbs to render alongside the
  /// per-violation output.
  final List<ExplainEntry> explanations;

  int _analyzedFileCount = 0;
  int get analyzedFileCount => _analyzedFileCount;
  void attachAnalyzedFileCount(int n) => _analyzedFileCount = n;

  bool hasSeverityAtLeast(Severity s) {
    for (final m in metrics) {
      final w = m.worstSeverity;
      if (w != null && w.rank >= s.rank) return true;
    }
    return false;
  }

  Map<String, Object?> toJson() => {
    'version': version,
    if (analyzedFiles.isNotEmpty)
      'analyzedFiles': analyzedFiles.map((f) => f.toJson()).toList(),
    'metrics': metrics.map((m) => m.toJson()).toList(),
    'unused': unused.map((u) => u.toJson()).toList(),
  };
}
