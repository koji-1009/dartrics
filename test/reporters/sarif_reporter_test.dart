import 'dart:convert';
import 'dart:io';

import 'package:dartrics/src/models/analysis_report.dart';
import 'package:dartrics/src/models/source_location.dart';
import 'package:dartrics/src/reporters/sarif_reporter.dart';
import 'package:test/test.dart';

import 'sample_report.dart';

void main() {
  test(
    'emits SARIF 2.1.0 envelope with one result per violation/unused',
    () async {
      final tmp = Directory.systemTemp.createTempSync();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final out = File('${tmp.path}/r.sarif');
      final sink = out.openWrite();
      SarifReporter().report(buildSampleReport(), sink);
      await sink.close();

      final doc = jsonDecode(out.readAsStringSync()) as Map<String, Object?>;
      expect(doc['version'], '2.1.0');
      final runs = doc['runs'] as List;
      expect(runs, hasLength(1));
      final results = (runs.first as Map)['results'] as List;
      // 1 metric violation + 1 unused = 2 results
      expect(results, hasLength(2));
      final ruleIds = results.map((r) => (r as Map)['ruleId']).toSet();
      expect(
        ruleIds,
        containsAll(['cyclomatic-complexity', 'unused-declaration']),
      );
    },
  );

  test(
    'tool.driver.rules carries rationale + refactor hints for fired metrics',
    () async {
      final tmp = Directory.systemTemp.createTempSync();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final out = File('${tmp.path}/r.sarif');
      final sink = out.openWrite();
      SarifReporter().report(buildSampleReport(), sink);
      await sink.close();

      final doc = jsonDecode(out.readAsStringSync()) as Map<String, Object?>;
      final rules =
          ((doc['runs'] as List).first as Map)['tool'] as Map<String, Object?>?;
      final driverRules = ((rules!['driver'] as Map)['rules'] as List)
          .cast<Map<String, Object?>>();
      // sample report uses cyclomatic-complexity + an unused declaration.
      final cc = driverRules.firstWhere(
        (r) => r['id'] == 'cyclomatic-complexity',
      );
      expect(cc['name'], 'CyclomaticComplexity');
      expect((cc['fullDescription'] as Map)['text'], contains('McCabe'));
      expect(
        cc['helpUri'],
        'https://pub.dev/packages/dartrics#provided-metrics',
      );
      final help = cc['help'] as Map<String, Object?>;
      expect(help['text'], contains('Refactor hints:'));
      expect(help['markdown'], contains('**Refactor hints:**'));
      // References list is rendered into both the plain-text and the
      // markdown help blocks so SARIF consumers (GitHub Code Scanning,
      // VS Code's SARIF viewer) surface the citation alongside the
      // rationale + refactor hints.
      expect(help['text'], contains('References:'));
      expect(help['markdown'], contains('**References:**'));
      expect(help['text'], contains('McCabe'));
      final props = cc['properties'] as Map<String, Object?>;
      expect((props['tags'] as List), containsAll(['dartrics', 'function']));
      expect(props['defaultThreshold'], 10);

      final unused = driverRules.firstWhere(
        (r) => r['id'] == 'unused-declaration',
      );
      expect(unused['name'], 'UnusedDeclaration');
      expect(
        (unused['fullDescription'] as Map)['text'],
        contains('Periphery-style'),
      );
    },
  );

  test(
    'falls back to bare id when a metric has no registered description',
    () async {
      final tmp = Directory.systemTemp.createTempSync();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final out = File('${tmp.path}/r.sarif');
      final report = AnalysisReport(
        version: '1.0',
        metrics: [
          const MetricRecord(
            file: 'lib/foo.dart',
            scope: ScopeRef(
              kind: ScopeKind.function,
              name: 'foo',
              location: SourceLocation(
                path: 'lib/foo.dart',
                line: 1,
                column: 1,
              ),
            ),
            values: {'custom-embedder-metric': 99},
            violations: [
              MetricViolation(
                id: 'abcdef0123456789',
                metricId: 'custom-embedder-metric',
                severity: Severity.warning,
                threshold: 1,
              ),
            ],
          ),
        ],
        unused: const [],
      );
      final sink = out.openWrite();
      SarifReporter().report(report, sink);
      await sink.close();
      final doc = jsonDecode(out.readAsStringSync()) as Map<String, Object?>;
      final driverRules =
          ((((doc['runs'] as List).first as Map)['tool'] as Map)['driver']
                  as Map)['rules']
              as List;
      final entry = driverRules.first as Map<String, Object?>;
      expect(entry['id'], 'custom-embedder-metric');
      expect(entry.containsKey('fullDescription'), isFalse);
    },
  );
}
