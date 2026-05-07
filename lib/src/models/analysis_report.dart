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
enum ScopeKind { function, method, klass, library }

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
    this.id = '',
    this.scopeCoverage,
    this.scopeBranchCoverage,
    this.complexityJustified = false,
    this.complexityJustifiedBy,
    this.complexityJustifiedThreshold,
    this.dismissed = false,
    this.dismissReason,
    this.dismissedBy,
    this.dismissedAt,
    this.dismissedFrom,
    this.dismissalRejected,
  });

  /// Stable identifier for this `(file, scope, metric)` triple. The first
  /// 16 hex chars of `sha256("<file>|<scope>|<metricId>")` — collisions
  /// at 64 bits are not a practical concern for any single project.
  ///
  /// Empty string in the const default constructor purely so the
  /// pre-id-bearing fixtures keep compiling; the engine sets it on
  /// every emitted violation. AI loops can correlate across runs:
  /// "id `a3f1c4e9…` showed up again ⇒ my last refactor missed it."
  final String id;

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

  /// Which coverage rule triggered [complexityJustified]: `'branch'`
  /// when branch coverage data was available and crossed its
  /// threshold, or `'line'` when branch data was missing and line
  /// coverage was used as the more conservative fallback. `null` when
  /// [complexityJustified] is false. Surfaces the engine's decision
  /// path so AI loops can override the heuristic with their own
  /// thresholds, and so reports stay self-describing instead of relying
  /// on documentation to explain how the bool was derived.
  final String? complexityJustifiedBy;

  /// The threshold that [complexityJustifiedBy]'s coverage value had
  /// to cross. Currently 0.8 for branch and 0.95 for line — exposed
  /// here so consumers see the literal value rather than reading it
  /// out of the engine source. `null` when [complexityJustified] is
  /// false.
  final double? complexityJustifiedThreshold;

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
    if (id.isNotEmpty) 'id': id,
    'metric': metricId,
    'level': severity.name,
    'threshold': threshold,
    if (scopeCoverage != null) 'scopeCoverage': scopeCoverage,
    if (scopeBranchCoverage != null) 'scopeBranchCoverage': scopeBranchCoverage,
    if (complexityJustified) 'complexityJustified': true,
    if (complexityJustifiedBy != null)
      'complexityJustifiedBy': complexityJustifiedBy,
    if (complexityJustifiedThreshold != null)
      'complexityJustifiedThreshold': complexityJustifiedThreshold,
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
    this.staleDismissals = const [],
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

  /// Dismissals that were configured (in `dartrics-dismissals.yaml` or
  /// as `// dartrics:dismiss` comments) but that never matched a live
  /// violation in the analyzed file set. AI loops can use these to
  /// clean the dismiss file before stale entries accumulate.
  /// Populated only when `dartrics: { dismissals: { warnStale: true } }`
  /// (the default) and the engine has finished walking violations.
  final List<StaleDismissal> staleDismissals;

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
    if (staleDismissals.isNotEmpty)
      'staleDismissals': staleDismissals.map((s) => s.toJson()).toList(),
  };
}

/// One dismissal entry that never matched a live violation. Surfaced
/// in the report so AI loops can prune dead entries.
class StaleDismissal {
  const StaleDismissal({
    required this.file,
    required this.scope,
    required this.metricId,
    required this.source,
    this.reason,
  });

  /// Project-relative file path the dismissal targeted.
  final String file;

  /// Scope name (`Foo.bar`) the dismissal targeted.
  final String scope;

  /// Metric id (`cyclomatic-complexity`) the dismissal targeted.
  final String metricId;

  /// Which channel the dismissal came from — comment or YAML. AI loops
  /// use this to know whether the cleanup is a source edit or a YAML
  /// edit.
  final DismissalSource source;

  /// Original `reason:` text from the dismissal, kept for context so
  /// the cleanup decision can be informed. `null` when the dismissal
  /// had no reason and `requireReason` was off.
  final String? reason;

  Map<String, Object?> toJson() => {
    'file': file,
    'scope': scope,
    'metric': metricId,
    'source': source.name,
    if (reason != null) 'reason': reason,
  };
}
