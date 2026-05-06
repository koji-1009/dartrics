import '../metrics/class/default_class_metrics.dart';
import '../metrics/function/default_function_metrics.dart';
import '../metrics/library/default_library_metrics.dart';
import '../metrics/metric.dart';
import '../models/analysis_report.dart';
import '../models/regression_report.dart';

/// Configuration constants for the cosmetic-split heuristic. Exposed so
/// tests can pin them and so future configurability has one place to
/// touch.
class RegressionConfig {
  const RegressionConfig({this.smallBodyThreshold = 3});

  /// Maximum SLOC of a function body that still counts as "tiny" for
  /// the cosmetic-split heuristic.
  final int smallBodyThreshold;
}

/// Computes a [RegressionReport] from two `dartrics analyze` runs.
class RegressionDiff {
  const RegressionDiff({this.config = const RegressionConfig()});

  final RegressionConfig config;

  /// Build the per-metric polarity table by walking every default
  /// metric calculator. Stable across runs because the metric set is
  /// itself stable.
  static Map<String, MetricPolarity> _buildPolarityTable() {
    final out = <String, MetricPolarity>{};
    for (final m in defaultFunctionMetrics) {
      out[m.id] = m.polarity;
    }
    for (final m in defaultClassMetrics) {
      out[m.id] = m.polarity;
    }
    for (final m in defaultLibraryMetrics) {
      out[m.id] = m.polarity;
    }
    return out;
  }

  /// Compute the diff. [focusMetrics] restricts the output to the named
  /// metric ids; an empty / null set means "all metrics".
  RegressionReport compute({
    required String beforeLabel,
    required String afterLabel,
    required List<MetricRecord> beforeRecords,
    required List<MetricRecord> afterRecords,
    Set<String>? focusMetrics,
  }) {
    final polarity = _buildPolarityTable();
    final beforeIndex = _index(beforeRecords);
    final afterIndex = _index(afterRecords);

    final changes = <MetricChange>[];
    final keys = {...beforeIndex.keys, ...afterIndex.keys};
    for (final key in keys) {
      final before = beforeIndex[key];
      final after = afterIndex[key];
      changes.addAll(
        _changesFor(
          key: key,
          before: before,
          after: after,
          polarity: polarity,
          focus: focusMetrics,
        ),
      );
    }
    changes.sort(_changeComparator);

    return RegressionReport(
      before: beforeLabel,
      after: afterLabel,
      changes: changes,
      summary: RegressionSummary.fromChanges(changes),
      cosmetic: _cosmeticSignals(
        beforeIndex: beforeIndex,
        afterIndex: afterIndex,
      ),
    );
  }

  Iterable<MetricChange> _changesFor({
    required _ScopeKey key,
    required MetricRecord? before,
    required MetricRecord? after,
    required Map<String, MetricPolarity> polarity,
    required Set<String>? focus,
  }) sync* {
    final metricIds = <String>{...?before?.values.keys, ...?after?.values.keys};
    for (final id in metricIds) {
      if (focus != null && focus.isNotEmpty && !focus.contains(id)) continue;
      final beforeValue = before?.values[id];
      final afterValue = after?.values[id];
      yield MetricChange(
        file: (after ?? before!).file,
        scope: (after ?? before!).scope,
        metricId: id,
        before: beforeValue,
        after: afterValue,
        direction: _classify(
          before: beforeValue,
          after: afterValue,
          polarity: polarity[id] ?? MetricPolarity.neutral,
          scopeAdded: before == null,
          scopeRemoved: after == null,
        ),
      );
    }
  }

  ChangeDirection _classify({
    required num? before,
    required num? after,
    required MetricPolarity polarity,
    required bool scopeAdded,
    required bool scopeRemoved,
  }) {
    if (scopeAdded) return ChangeDirection.added;
    if (scopeRemoved) return ChangeDirection.removed;
    if (before == null || after == null || before == after) {
      return ChangeDirection.unchanged;
    }
    switch (polarity) {
      case MetricPolarity.down:
        return after < before
            ? ChangeDirection.improved
            : ChangeDirection.regressed;
      case MetricPolarity.up:
        return after > before
            ? ChangeDirection.improved
            : ChangeDirection.regressed;
      case MetricPolarity.neutral:
        return ChangeDirection.neutralDelta;
    }
  }

  CosmeticSignals _cosmeticSignals({
    required Map<_ScopeKey, MetricRecord> beforeIndex,
    required Map<_ScopeKey, MetricRecord> afterIndex,
  }) {
    var tinyHelpersAdded = 0;
    var slocDelta = 0;
    var ccReduction = 0;

    for (final entry in afterIndex.entries) {
      final key = entry.key;
      final after = entry.value;
      final before = beforeIndex[key];
      final afterScope = after.scope.kind;
      final isFunctionish =
          afterScope == ScopeKind.function || afterScope == ScopeKind.method;
      if (before == null && isFunctionish) {
        final sloc = (after.values['source-lines-of-code'] ?? 0).toInt();
        if (sloc <= config.smallBodyThreshold) {
          tinyHelpersAdded++;
        }
      }
      final beforeSloc = (before?.values['source-lines-of-code'] ?? 0).toInt();
      final afterSloc = (after.values['source-lines-of-code'] ?? 0).toInt();
      slocDelta += afterSloc - beforeSloc;
      if (before != null) {
        final beforeCc = (before.values['cyclomatic-complexity'] ?? 0).toInt();
        final afterCc = (after.values['cyclomatic-complexity'] ?? 0).toInt();
        if (afterCc < beforeCc) ccReduction += beforeCc - afterCc;
      }
    }
    // Also subtract SLOC for scopes that disappeared (deleted code).
    for (final entry in beforeIndex.entries) {
      if (afterIndex.containsKey(entry.key)) continue;
      final sloc = (entry.value.values['source-lines-of-code'] ?? 0).toInt();
      slocDelta -= sloc;
    }

    return CosmeticSignals(
      tinyHelpersAdded: tinyHelpersAdded,
      slocDelta: slocDelta,
      ccReduction: ccReduction,
      smallBodyThreshold: config.smallBodyThreshold,
    );
  }

  Map<_ScopeKey, MetricRecord> _index(List<MetricRecord> records) {
    final out = <_ScopeKey, MetricRecord>{};
    for (final r in records) {
      out[_ScopeKey(file: r.file, kind: r.scope.kind, name: r.scope.name)] = r;
    }
    return out;
  }

  int _changeComparator(MetricChange a, MetricChange b) {
    final byDir = _directionOrder(
      a.direction,
    ).compareTo(_directionOrder(b.direction));
    if (byDir != 0) return byDir;
    final byFile = a.file.compareTo(b.file);
    if (byFile != 0) return byFile;
    final byScope = a.scope.name.compareTo(b.scope.name);
    if (byScope != 0) return byScope;
    return a.metricId.compareTo(b.metricId);
  }

  int _directionOrder(ChangeDirection d) {
    // Regressions first (loudest), then improvements, then bookkeeping.
    switch (d) {
      case ChangeDirection.regressed:
        return 0;
      case ChangeDirection.added:
        return 1;
      case ChangeDirection.removed:
        return 2;
      case ChangeDirection.improved:
        return 3;
      case ChangeDirection.neutralDelta:
        return 4;
      case ChangeDirection.unchanged:
        return 5;
    }
  }
}

class _ScopeKey {
  const _ScopeKey({required this.file, required this.kind, required this.name});

  final String file;
  final ScopeKind kind;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is _ScopeKey &&
      other.file == file &&
      other.kind == kind &&
      other.name == name;

  @override
  int get hashCode => Object.hash(file, kind, name);
}
