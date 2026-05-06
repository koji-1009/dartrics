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

  test('ai reporter renders a cosmetic warning when looksCosmetic', () async {
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
    expect(body, contains('refactor looks cosmetic'));
    expect(body, contains('changes:'));
  });

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
    'console reporter prints WARNING line on cosmetic looksCosmetic',
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
