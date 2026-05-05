import 'dart:convert';
import 'dart:io';

import 'package:dartrics/src/models/analysis_report.dart';
import 'package:dartrics/src/models/source_location.dart';
import 'package:dartrics/src/reporters/sarif_reporter.dart';
import 'package:test/test.dart';

void main() {
  test('Severity.info maps to SARIF "note" level', () async {
    final report = AnalysisReport(
      version: '1.0',
      metrics: const [
        MetricRecord(
          file: 'a.dart',
          scope: ScopeRef(
            kind: ScopeKind.function,
            name: 'f',
            location: SourceLocation(path: 'a.dart', line: 1, column: 1),
          ),
          values: {'style-hint': 1},
          violations: [
            MetricViolation(
              metricId: 'style-hint',
              severity: Severity.info,
              threshold: 0,
            ),
          ],
        ),
      ],
      unused: const [],
    )..attachAnalyzedFileCount(1);

    final dir = await Directory.systemTemp.createTemp('sarif_info_');
    addTearDown(() => dir.delete(recursive: true));
    final out = File('${dir.path}/r.sarif');
    final sink = out.openWrite();
    SarifReporter().report(report, sink);
    await sink.close();

    final doc = jsonDecode(out.readAsStringSync()) as Map<String, Object?>;
    final results = ((doc['runs'] as List).first as Map)['results'] as List;
    expect(results.first, containsPair('level', 'note'));
  });
}
