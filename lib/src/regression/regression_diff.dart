import '../metrics/class/default_class_metrics.dart';
import '../metrics/function/default_function_metrics.dart';
import '../metrics/library/default_library_metrics.dart';
import '../metrics/metric.dart';
import '../models/analysis_report.dart';
import '../models/regression_report.dart';

/// Configuration constants for the cosmetic-split heuristic.
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
  }) => classifyChange(
    before: before,
    after: after,
    polarity: polarity,
    scopeAdded: scopeAdded,
    scopeRemoved: scopeRemoved,
  );

  CosmeticSignals _cosmeticSignals({
    required Map<_ScopeKey, MetricRecord> beforeIndex,
    required Map<_ScopeKey, MetricRecord> afterIndex,
  }) {
    var tinyHelpersAdded = 0;
    var slocDelta = 0;
    var ccReduction = 0;
    for (final entry in afterIndex.entries) {
      final delta = _scopeContribution(beforeIndex[entry.key], entry.value);
      tinyHelpersAdded += delta.tinyHelpers;
      slocDelta += delta.slocDelta;
      ccReduction += delta.ccReduction;
    }
    // Subtract SLOC for scopes that disappeared (deleted code).
    for (final entry in beforeIndex.entries) {
      if (afterIndex.containsKey(entry.key)) continue;
      slocDelta -= _slocOf(entry.value);
    }
    return CosmeticSignals(
      tinyHelpersAdded: tinyHelpersAdded,
      slocDelta: slocDelta,
      ccReduction: ccReduction,
      smallBodyThreshold: config.smallBodyThreshold,
    );
  }

  /// Per-scope contribution to the cosmetic-split detector — the
  /// "tiny new helper?" flag + SLOC delta + CC reduction.
  ({int tinyHelpers, int slocDelta, int ccReduction}) _scopeContribution(
    MetricRecord? before,
    MetricRecord after,
  ) {
    final tinyHelpers = _isNewTinyFunction(before, after) ? 1 : 0;
    final slocDelta = _slocOf(after) - (before == null ? 0 : _slocOf(before));
    final ccReduction = _ccReduction(before, after);
    return (
      tinyHelpers: tinyHelpers,
      slocDelta: slocDelta,
      ccReduction: ccReduction,
    );
  }

  bool _isNewTinyFunction(MetricRecord? before, MetricRecord after) {
    if (before != null) return false;
    final kind = after.scope.kind;
    if (kind != ScopeKind.function && kind != ScopeKind.method) return false;
    return _slocOf(after) <= config.smallBodyThreshold;
  }

  int _ccReduction(MetricRecord? before, MetricRecord after) {
    if (before == null) return 0;
    final beforeCc = (before.values['cyclomatic-complexity'] ?? 0).toInt();
    final afterCc = (after.values['cyclomatic-complexity'] ?? 0).toInt();
    return afterCc < beforeCc ? beforeCc - afterCc : 0;
  }

  int _slocOf(MetricRecord r) =>
      (r.values['source-lines-of-code'] ?? 0).toInt();

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

/// Classifies a metric value change between two runs given the
/// metric's [polarity] and whether the scope was added or removed.
ChangeDirection classifyChange({
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
  return _directionByPolarity(before: before, after: after, polarity: polarity);
}

/// Polarity-aware leg of [classifyChange]. Both inputs are guaranteed
/// non-null and unequal at this point — the caller has already
/// short-circuited those cases.
ChangeDirection _directionByPolarity({
  required num before,
  required num after,
  required MetricPolarity polarity,
}) {
  switch (polarity) {
    case MetricPolarity.down:
      return after < before
          ? ChangeDirection.improved
          : ChangeDirection.regressed;
    case MetricPolarity.neutral:
      return ChangeDirection.neutralDelta;
  }
}
