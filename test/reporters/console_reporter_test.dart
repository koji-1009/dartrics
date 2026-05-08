import 'dart:io';

import 'package:dartrics/src/models/analysis_report.dart';
import 'package:dartrics/src/models/source_location.dart';
import 'package:dartrics/src/reporters/console_reporter.dart';
import 'package:test/test.dart';

import 'sample_report.dart';

void main() {
  test(
    'writes summary line plus per-violation and per-unused entries',
    () async {
      final dir = await Directory.systemTemp.createTemp('console_reporter_');
      addTearDown(() => dir.delete(recursive: true));
      final out = File('${dir.path}/r.txt');
      final sink = out.openWrite();
      ConsoleReporter().report(buildSampleReport(), sink);
      await sink.close();
      final body = await out.readAsString();
      expect(body, contains('analyzed'));
      expect(body, contains('cyclomatic-complexity'));
      expect(body, contains('Foo.bar'));
      expect(body, contains('_legacyFormatter'));
    },
  );

  test('appends snapshot suffix when a diff filter is active', () async {
    final dir = await Directory.systemTemp.createTemp('console_reporter_snap_');
    addTearDown(() => dir.delete(recursive: true));
    final out = File('${dir.path}/r.txt');
    final sink = out.openWrite();
    ConsoleReporter().report(
      AnalysisReport(
        version: '1.0',
        metrics: const [],
        unused: const [],
        snapshotMode: 'cache',
        changedFileCount: 0,
      )..attachAnalyzedFileCount(3),
      sink,
    );
    await sink.close();
    final body = await out.readAsString();
    expect(body, contains('[snapshot cache: 0 of 3 changed]'));
  });

  test('annotates dismissed and dismissal-rejected violations', () async {
    final dir = await Directory.systemTemp.createTemp('console_reporter_dis_');
    addTearDown(() => dir.delete(recursive: true));
    final out = File('${dir.path}/r.txt');
    final sink = out.openWrite();
    final report = AnalysisReport(
      version: '1.0',
      metrics: const [
        MetricRecord(
          file: '/proj/d.dart',
          scope: ScopeRef(
            kind: ScopeKind.function,
            name: 'silenced',
            location: SourceLocation(path: '/proj/d.dart', line: 1, column: 1),
          ),
          values: {'cyclomatic-complexity': 11},
          violations: [
            MetricViolation(
              metricId: 'cyclomatic-complexity',
              severity: Severity.warning,
              threshold: 10,
              dismissed: true,
              dismissReason: 'state machine: splits hide intent',
            ),
            MetricViolation(
              metricId: 'method-length',
              severity: Severity.warning,
              threshold: 30,
              dismissalRejected: 'reason too short (need >= 20)',
            ),
          ],
        ),
      ],
      unused: [],
    );
    ConsoleReporter().report(report, sink);
    await sink.close();
    final body = await out.readAsString();
    expect(body, contains('[dismissed]'));
    expect(body, contains('[dismissal-rejected]'));
  });
}
