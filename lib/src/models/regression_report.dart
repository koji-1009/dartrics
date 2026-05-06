import '../metrics/metric.dart';
import 'analysis_report.dart';

/// Direction of a per-scope, per-metric value change between two
/// dartrics runs.
enum ChangeDirection {
  /// Metric value moved towards healthier per its [MetricPolarity].
  improved,

  /// Metric value moved away from healthier.
  regressed,

  /// Same numeric value before and after.
  unchanged,

  /// Polarity is neutral — a delta is recorded but not classified.
  neutralDelta,

  /// Scope existed in `after` but not in `before` (newly added code).
  added,

  /// Scope existed in `before` but not in `after` (deleted / renamed code).
  removed,
}

/// One row of the regression diff: a metric value's transition for a
/// single scope (file + scope name + metric id).
class MetricChange {
  const MetricChange({
    required this.file,
    required this.scope,
    required this.metricId,
    required this.before,
    required this.after,
    required this.direction,
  });

  final String file;
  final ScopeRef scope;
  final String metricId;

  /// `null` when the scope is newly added.
  final num? before;

  /// `null` when the scope was removed.
  final num? after;

  final ChangeDirection direction;

  Map<String, Object?> toJson() => {
    'file': file,
    'scope': scope.toJson(),
    'metric': metricId,
    'before': before,
    'after': after,
    'direction': direction.name,
  };
}

/// Aggregate counts across the [MetricChange] set, keyed by direction.
class RegressionSummary {
  const RegressionSummary({
    required this.improved,
    required this.regressed,
    required this.unchanged,
    required this.neutralDelta,
    required this.added,
    required this.removed,
  });

  factory RegressionSummary.fromChanges(Iterable<MetricChange> changes) {
    var improved = 0;
    var regressed = 0;
    var unchanged = 0;
    var neutralDelta = 0;
    var added = 0;
    var removed = 0;
    for (final c in changes) {
      switch (c.direction) {
        case ChangeDirection.improved:
          improved++;
        case ChangeDirection.regressed:
          regressed++;
        case ChangeDirection.unchanged:
          unchanged++;
        case ChangeDirection.neutralDelta:
          neutralDelta++;
        case ChangeDirection.added:
          added++;
        case ChangeDirection.removed:
          removed++;
      }
    }
    return RegressionSummary(
      improved: improved,
      regressed: regressed,
      unchanged: unchanged,
      neutralDelta: neutralDelta,
      added: added,
      removed: removed,
    );
  }

  final int improved;
  final int regressed;
  final int unchanged;
  final int neutralDelta;
  final int added;
  final int removed;

  Map<String, Object?> toJson() => {
    'improved': improved,
    'regressed': regressed,
    'unchanged': unchanged,
    'neutralDelta': neutralDelta,
    'added': added,
    'removed': removed,
  };
}

/// Heuristic signals that try to tell substantive refactors apart from
/// cosmetic ones (e.g. AI extracting a stream of one-line helpers just
/// to lower cyclomatic complexity).
class CosmeticSignals {
  const CosmeticSignals({
    required this.tinyHelpersAdded,
    required this.slocDelta,
    required this.ccReduction,
    required this.smallBodyThreshold,
  });

  /// Newly added function-shaped declarations whose body SLOC is at most
  /// [smallBodyThreshold].
  final int tinyHelpersAdded;

  /// Change in total source lines of code between before and after,
  /// summed across all matched scopes (positive = grew).
  final int slocDelta;

  /// Sum of cyclomatic-complexity reductions across matched scopes
  /// (positive = improved).
  final int ccReduction;

  /// Threshold for what counts as a "tiny" helper.
  final int smallBodyThreshold;

  /// True when the diff matches a cosmetic-split signature: several new
  /// tiny helpers, total SLOC grew faster than they justified, and the
  /// cyclomatic-complexity reduction is small per helper.
  bool get looksCosmetic =>
      tinyHelpersAdded >= 3 &&
      slocDelta > tinyHelpersAdded * 4 &&
      ccReduction < tinyHelpersAdded * 2;

  Map<String, Object?> toJson() => {
    'tinyHelpersAdded': tinyHelpersAdded,
    'slocDelta': slocDelta,
    'ccReduction': ccReduction,
    'smallBodyThreshold': smallBodyThreshold,
    'looksCosmetic': looksCosmetic,
  };
}

/// Top-level regression diff between two dartrics runs.
class RegressionReport {
  const RegressionReport({
    required this.before,
    required this.after,
    required this.changes,
    required this.summary,
    required this.cosmetic,
  });

  /// Label of the `before` state (git ref or descriptor).
  final String before;

  /// Label of the `after` state.
  final String after;

  final List<MetricChange> changes;
  final RegressionSummary summary;
  final CosmeticSignals cosmetic;

  Map<String, Object?> toJson() => {
    'version': '1.0',
    'before': before,
    'after': after,
    'summary': summary.toJson(),
    'cosmetic': cosmetic.toJson(),
    'changes': changes.map((c) => c.toJson()).toList(),
  };
}
