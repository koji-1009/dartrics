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
  });

  final String metricId;
  final Severity severity;
  final num threshold;

  Map<String, Object?> toJson() => {
        'metric': metricId,
        'level': severity.name,
        'threshold': threshold,
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

/// Top-level result returned by the analyzer.
class AnalysisReport {
  AnalysisReport({
    required this.version,
    required this.metrics,
    required this.unused,
  });

  final String version;
  final List<MetricRecord> metrics;
  final List<UnusedDeclaration> unused;

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
        'metrics': metrics.map((m) => m.toJson()).toList(),
        'unused': unused.map((u) => u.toJson()).toList(),
      };
}
