import 'package:dartrics/src/metrics/metric.dart';
import 'package:dartrics/src/models/analysis_report.dart';
import 'package:dartrics/src/models/regression_report.dart';
import 'package:dartrics/src/models/source_location.dart';
import 'package:dartrics/src/regression/regression_diff.dart';
import 'package:test/test.dart';

void main() {
  MetricRecord record({
    required String file,
    required ScopeKind kind,
    required String name,
    required Map<String, num> values,
  }) => MetricRecord(
    file: file,
    scope: ScopeRef(
      kind: kind,
      name: name,
      location: SourceLocation(path: file, line: 1, column: 1),
    ),
    values: values,
    violations: const [],
  );

  test('classifies a CC drop on the same scope as improved', () {
    final before = [
      record(
        file: 'lib/foo.dart',
        kind: ScopeKind.function,
        name: 'foo',
        values: const {'cyclomatic-complexity': 12},
      ),
    ];
    final after = [
      record(
        file: 'lib/foo.dart',
        kind: ScopeKind.function,
        name: 'foo',
        values: const {'cyclomatic-complexity': 8},
      ),
    ];
    final report = const RegressionDiff().compute(
      beforeLabel: 'before',
      afterLabel: 'after',
      beforeRecords: before,
      afterRecords: after,
    );
    expect(report.summary.improved, 1);
    expect(report.summary.regressed, 0);
    expect(report.changes.single.direction, ChangeDirection.improved);
  });

  test('classifies a CC growth as regressed', () {
    final before = [
      record(
        file: 'lib/foo.dart',
        kind: ScopeKind.function,
        name: 'foo',
        values: const {'cyclomatic-complexity': 5},
      ),
    ];
    final after = [
      record(
        file: 'lib/foo.dart',
        kind: ScopeKind.function,
        name: 'foo',
        values: const {'cyclomatic-complexity': 9},
      ),
    ];
    final report = const RegressionDiff().compute(
      beforeLabel: 'before',
      afterLabel: 'after',
      beforeRecords: before,
      afterRecords: after,
    );
    expect(report.summary.regressed, 1);
    expect(report.changes.single.direction, ChangeDirection.regressed);
  });

  test('classifyChange treats up-polarity drops as regressed', () {
    // No built-in metric currently uses up polarity; exercise the
    // public helper directly with a synthetic polarity.
    expect(
      classifyChange(
        before: 120,
        after: 100,
        polarity: MetricPolarity.up,
        scopeAdded: false,
        scopeRemoved: false,
      ),
      ChangeDirection.regressed,
    );
  });

  test('classifyChange treats up-polarity rises as improved', () {
    expect(
      classifyChange(
        before: 100,
        after: 120,
        polarity: MetricPolarity.up,
        scopeAdded: false,
        scopeRemoved: false,
      ),
      ChangeDirection.improved,
    );
  });

  test('flags neutral-polarity metric deltas without classifying them', () {
    final before = [
      record(
        file: 'lib/foo.dart',
        kind: ScopeKind.library,
        name: 'lib/foo.dart',
        values: const {'instability': 0.2},
      ),
    ];
    final after = [
      record(
        file: 'lib/foo.dart',
        kind: ScopeKind.library,
        name: 'lib/foo.dart',
        values: const {'instability': 0.7},
      ),
    ];
    final report = const RegressionDiff().compute(
      beforeLabel: 'b',
      afterLabel: 'a',
      beforeRecords: before,
      afterRecords: after,
    );
    expect(report.summary.improved, 0);
    expect(report.summary.regressed, 0);
    expect(report.summary.neutralDelta, 1);
    expect(report.changes.single.direction, ChangeDirection.neutralDelta);
  });

  test('classifies new scopes as added and removed scopes as removed', () {
    final before = [
      record(
        file: 'lib/foo.dart',
        kind: ScopeKind.function,
        name: 'gone',
        values: const {'cyclomatic-complexity': 1},
      ),
    ];
    final after = [
      record(
        file: 'lib/foo.dart',
        kind: ScopeKind.function,
        name: 'fresh',
        values: const {'cyclomatic-complexity': 1},
      ),
    ];
    final report = const RegressionDiff().compute(
      beforeLabel: 'b',
      afterLabel: 'a',
      beforeRecords: before,
      afterRecords: after,
    );
    expect(report.summary.added, 1);
    expect(report.summary.removed, 1);
  });

  test('focusMetrics restricts the diff to the named ids', () {
    final before = [
      record(
        file: 'lib/foo.dart',
        kind: ScopeKind.function,
        name: 'foo',
        values: const {'cyclomatic-complexity': 5, 'method-length': 20},
      ),
    ];
    final after = [
      record(
        file: 'lib/foo.dart',
        kind: ScopeKind.function,
        name: 'foo',
        values: const {'cyclomatic-complexity': 3, 'method-length': 30},
      ),
    ];
    final report = const RegressionDiff().compute(
      beforeLabel: 'b',
      afterLabel: 'a',
      beforeRecords: before,
      afterRecords: after,
      focusMetrics: const {'cyclomatic-complexity'},
    );
    expect(report.changes, hasLength(1));
    expect(report.changes.single.metricId, 'cyclomatic-complexity');
  });

  test('detects a cosmetic-split signature', () {
    // Five new tiny functions, total SLOC grew by 25, CC reduction = 4.
    // Heuristic threshold: tinyHelpersAdded >= 3 (5 ≥ 3 ✓),
    //                     slocDelta > tinyHelpersAdded * 4 (25 > 20 ✓),
    //                     ccReduction < tinyHelpersAdded * 2 (4 < 10 ✓)
    final before = [
      record(
        file: 'lib/foo.dart',
        kind: ScopeKind.function,
        name: 'big',
        values: const {'cyclomatic-complexity': 12, 'source-lines-of-code': 30},
      ),
    ];
    final after = [
      record(
        file: 'lib/foo.dart',
        kind: ScopeKind.function,
        name: 'big',
        values: const {'cyclomatic-complexity': 8, 'source-lines-of-code': 40},
      ),
      for (var i = 0; i < 5; i++)
        record(
          file: 'lib/foo.dart',
          kind: ScopeKind.function,
          name: 'helper$i',
          values: const {'cyclomatic-complexity': 1, 'source-lines-of-code': 3},
        ),
    ];
    final report = const RegressionDiff().compute(
      beforeLabel: 'b',
      afterLabel: 'a',
      beforeRecords: before,
      afterRecords: after,
    );
    expect(report.cosmetic.tinyHelpersAdded, 5);
    expect(report.cosmetic.looksCosmetic, isTrue);
  });

  test('does not flag a substantive refactor that extracts large helpers', () {
    final before = [
      record(
        file: 'lib/foo.dart',
        kind: ScopeKind.function,
        name: 'big',
        values: const {'cyclomatic-complexity': 14, 'source-lines-of-code': 60},
      ),
    ];
    final after = [
      record(
        file: 'lib/foo.dart',
        kind: ScopeKind.function,
        name: 'big',
        values: const {'cyclomatic-complexity': 4, 'source-lines-of-code': 18},
      ),
      record(
        file: 'lib/foo.dart',
        kind: ScopeKind.function,
        name: 'helper',
        values: const {'cyclomatic-complexity': 6, 'source-lines-of-code': 30},
      ),
    ];
    final report = const RegressionDiff().compute(
      beforeLabel: 'b',
      afterLabel: 'a',
      beforeRecords: before,
      afterRecords: after,
    );
    expect(report.cosmetic.looksCosmetic, isFalse);
  });

  test('unchanged values come last in the sorted change list', () {
    final shared = {'cyclomatic-complexity': 2};
    final before = [
      record(file: 'a', kind: ScopeKind.function, name: 'a', values: shared),
      record(
        file: 'b',
        kind: ScopeKind.function,
        name: 'b',
        values: const {'cyclomatic-complexity': 5},
      ),
    ];
    final after = [
      record(file: 'a', kind: ScopeKind.function, name: 'a', values: shared),
      record(
        file: 'b',
        kind: ScopeKind.function,
        name: 'b',
        values: const {'cyclomatic-complexity': 3},
      ),
    ];
    final report = const RegressionDiff().compute(
      beforeLabel: 'b',
      afterLabel: 'a',
      beforeRecords: before,
      afterRecords: after,
    );
    expect(report.changes.first.direction, ChangeDirection.improved);
    expect(report.changes.last.direction, ChangeDirection.unchanged);
  });

  test('toJson round-trips the headline fields', () {
    final report = const RegressionDiff().compute(
      beforeLabel: 'HEAD~1',
      afterLabel: 'HEAD',
      beforeRecords: const [],
      afterRecords: const [],
    );
    final json = report.toJson();
    expect(json['before'], 'HEAD~1');
    expect(json['after'], 'HEAD');
    expect(json['summary'], isA<Map<String, Object?>>());
    expect(json['cosmetic'], isA<Map<String, Object?>>());
  });
}
