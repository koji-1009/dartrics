import 'dart:io';

import 'package:dartrics/src/models/analysis_report.dart';
import 'package:dartrics/src/models/regression_report.dart';
import 'package:dartrics/src/models/source_location.dart';
import 'package:dartrics/src/reporters/regression_reporter.dart';
import 'package:test/test.dart';

void main() {
  RegressionReport build({
    required CosmeticSignals cosmetic,
    List<MetricChange> changes = const [],
  }) => RegressionReport(
    before: 'HEAD~1',
    after: 'HEAD',
    changes: changes,
    summary: RegressionSummary.fromChanges(changes),
    cosmetic: cosmetic,
  );

  MetricChange change(ChangeDirection direction) => MetricChange(
    file: 'lib/foo.dart',
    scope: const ScopeRef(
      kind: ScopeKind.function,
      name: 'foo',
      location: SourceLocation(path: 'lib/foo.dart', line: 1, column: 1),
    ),
    metricId: 'cyclomatic-complexity',
    before: 5,
    after: 3,
    direction: direction,
  );

  Future<String> render(RegressionReport report, String fmt) async {
    final tmp = await File.fromUri(
      Uri.file('${Directory.systemTemp.createTempSync().path}/r.$fmt'),
    ).create();
    final sink = tmp.openWrite();
    const RegressionReporter().report(report, sink, fmt);
    await sink.close();
    return tmp.readAsString();
  }

  test(
    'ai reporter renders a cosmetic warning when cosmeticSplitDetected',
    () async {
      final report = build(
        cosmetic: const CosmeticSignals(
          tinyHelpersAdded: 5,
          slocDelta: 25,
          ccReduction: 4,
          smallBodyThreshold: 3,
        ),
        changes: [change(ChangeDirection.improved)],
      );
      final body = await render(report, 'ai');
      expect(body, contains('warning:'));
      expect(body, contains('Cosmetic-split signature matched'));
      expect(body, contains('cosmeticSplitDetected: true'));
      expect(body, contains('changes:'));
      // Stable id for the (file, scope, metric) triple is emitted so AI
      // loops can correlate this row with the matching analyze violation.
      expect(body, contains('    id: ${report.changes.single.id}'));
    },
  );

  test('md reporter renders the cosmetic-split section', () async {
    final report = build(
      cosmetic: const CosmeticSignals(
        tinyHelpersAdded: 5,
        slocDelta: 25,
        ccReduction: 4,
        smallBodyThreshold: 3,
      ),
      changes: [change(ChangeDirection.improved)],
    );
    final body = await render(report, 'md');
    expect(body, contains('Cosmetic-split warning'));
    expect(body, contains('Changes'));
  });

  test('console reporter prints regressed entries', () async {
    final report = build(
      cosmetic: const CosmeticSignals(
        tinyHelpersAdded: 0,
        slocDelta: 0,
        ccReduction: 0,
        smallBodyThreshold: 3,
      ),
      changes: [change(ChangeDirection.regressed)],
    );
    final body = await render(report, 'console');
    expect(body, contains('regressed'));
  });

  test(
    'console reporter prints WARNING line on cosmeticSplitDetected',
    () async {
      final report = build(
        cosmetic: const CosmeticSignals(
          tinyHelpersAdded: 5,
          slocDelta: 25,
          ccReduction: 4,
          smallBodyThreshold: 3,
        ),
      );
      final body = await render(report, 'console');
      expect(body, contains('WARNING'));
      expect(body, contains('cosmetic-split signature matched'));
    },
  );

  test(
    'ai reporter emits cosmetic block with raw values when below threshold',
    () async {
      // 2 helpers added — under the looksCosmetic threshold (≥ 3).
      // The block should still render so AI loops can see the trend.
      final report = build(
        cosmetic: const CosmeticSignals(
          tinyHelpersAdded: 2,
          slocDelta: 8,
          ccReduction: 1,
          smallBodyThreshold: 3,
        ),
      );
      final body = await render(report, 'ai');
      expect(body, contains('cosmetic:'));
      expect(body, contains('tinyHelpersAdded: 2'));
      expect(body, contains('slocDelta: 8'));
      expect(body, contains('ccReduction: 1'));
      expect(body, contains('cosmeticSplitDetected: false'));
      // Below-threshold runs surface a clarifying comment so AI loops
      // don't read the bare `false` as a passing grade.
      expect(body, contains('narrow heuristic'));
      // Threshold-crossing warning should NOT appear.
      expect(body, isNot(contains('warning:')));
    },
  );

  test('md reporter renders Cosmetic signals section without warning when below threshold', () async {
    final report = build(
      cosmetic: const CosmeticSignals(
        tinyHelpersAdded: 2,
        slocDelta: 8,
        ccReduction: 1,
        smallBodyThreshold: 3,
      ),
    );
    final body = await render(report, 'md');
    expect(body, contains('Cosmetic signals'));
    expect(body, isNot(contains('Cosmetic-split warning')));
    expect(body, contains('tinyHelpersAdded: 2'));
    // Below-threshold sections still print the narrow-heuristic
    // disclaimer so human readers don't infer a passing grade either.
    expect(body, contains('Narrow heuristic'));
    expect(body, contains('cosmeticSplitDetected: false'));
  });

  test(
    'console reporter prefixes "cosmetic signals" when below threshold',
    () async {
      final report = build(
        cosmetic: const CosmeticSignals(
          tinyHelpersAdded: 2,
          slocDelta: 5,
          ccReduction: 1,
          smallBodyThreshold: 3,
        ),
      );
      final body = await render(report, 'console');
      expect(body, contains('cosmetic signals'));
      expect(body, isNot(contains('WARNING')));
    },
  );

  test(
    'reporters omit the cosmetic block entirely when all counters are 0',
    () async {
      final report = build(
        cosmetic: const CosmeticSignals(
          tinyHelpersAdded: 0,
          slocDelta: 0,
          ccReduction: 0,
          smallBodyThreshold: 3,
        ),
      );
      final ai = await render(report, 'ai');
      expect(ai, isNot(contains('cosmetic:')));
      final md = await render(report, 'md');
      expect(md, isNot(contains('Cosmetic')));
      final console = await render(report, 'console');
      expect(console, isNot(contains('cosmetic')));
    },
  );

  test('reporter accepts an empty change list', () async {
    final report = build(
      cosmetic: const CosmeticSignals(
        tinyHelpersAdded: 0,
        slocDelta: 0,
        ccReduction: 0,
        smallBodyThreshold: 3,
      ),
    );
    final ai = await render(report, 'ai');
    expect(ai, isNot(contains('changes:')));
    final md = await render(report, 'md');
    expect(md, isNot(contains('## Changes')));
  });
}
