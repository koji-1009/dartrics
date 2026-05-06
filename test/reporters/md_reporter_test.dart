import 'dart:io';

import 'package:dartrics/src/models/analysis_report.dart';
import 'package:dartrics/src/models/source_location.dart';
import 'package:dartrics/src/reporters/md_reporter.dart';
import 'package:test/test.dart';

import 'sample_report.dart';

void main() {
  test('emits sections, summary table, violations, unused', () async {
    final temp = await File.fromUri(
      Uri.file('${Directory.systemTemp.createTempSync().path}/r.md'),
    ).create();
    final sink = temp.openWrite();
    MdReporter().report(buildSampleReport(), sink);
    await sink.close();

    final body = await temp.readAsString();
    expect(body, contains('# dartrics report'));
    expect(body, contains('## Summary'));
    expect(body, contains('## Violations'));
    expect(body, contains('Foo.bar'));
    expect(body, contains('cyclomatic-complexity'));
    expect(body, contains('## Unused Declarations'));
    expect(body, contains('_legacyFormatter'));
  });

  test('renders coverage and earned tag on the violation bullet', () async {
    final temp = await File.fromUri(
      Uri.file('${Directory.systemTemp.createTempSync().path}/r.md'),
    ).create();
    final sink = temp.openWrite();
    final report = AnalysisReport(
      version: '1.0',
      metrics: const [
        MetricRecord(
          file: '/proj/lib/foo.dart',
          scope: ScopeRef(
            kind: ScopeKind.method,
            name: 'Foo.bar',
            location: SourceLocation(
              path: '/proj/lib/foo.dart',
              line: 1,
              column: 1,
            ),
          ),
          values: {'cyclomatic-complexity': 12},
          violations: [
            MetricViolation(
              metricId: 'cyclomatic-complexity',
              severity: Severity.warning,
              threshold: 10,
              scopeCoverage: 0.97,
              complexityJustified: true,
            ),
          ],
        ),
      ],
      unused: const [],
    );
    MdReporter().report(report, sink);
    await sink.close();
    final body = await temp.readAsString();
    expect(body, contains('coverage 97%'));
    expect(body, contains('earned'));
  });

  test('renders dismissed and dismissal-rejected suffixes', () async {
    final temp = await File.fromUri(
      Uri.file('${Directory.systemTemp.createTempSync().path}/r.md'),
    ).create();
    final sink = temp.openWrite();
    final report = AnalysisReport(
      version: '1.0',
      metrics: const [
        MetricRecord(
          file: '/proj/lib/dis.dart',
          scope: ScopeRef(
            kind: ScopeKind.function,
            name: 'dismissed',
            location: SourceLocation(
              path: '/proj/lib/dis.dart',
              line: 1,
              column: 1,
            ),
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
          ],
        ),
        MetricRecord(
          file: '/proj/lib/rej.dart',
          scope: ScopeRef(
            kind: ScopeKind.function,
            name: 'rejected',
            location: SourceLocation(
              path: '/proj/lib/rej.dart',
              line: 1,
              column: 1,
            ),
          ),
          values: {'cyclomatic-complexity': 11},
          violations: [
            MetricViolation(
              metricId: 'cyclomatic-complexity',
              severity: Severity.warning,
              threshold: 10,
              dismissalRejected: 'reason too short (need >= 20)',
            ),
          ],
        ),
      ],
      unused: const [],
    );
    MdReporter().report(report, sink);
    await sink.close();
    final body = await temp.readAsString();
    expect(body, contains('_dismissed_'));
    expect(body, contains('_dismissal-rejected_'));
  });

  test(
    'renders an Explanations section when explanations are attached',
    () async {
      final temp = await File.fromUri(
        Uri.file('${Directory.systemTemp.createTempSync().path}/r.md'),
      ).create();
      final sink = temp.openWrite();
      MdReporter().report(
        buildSampleReport(
          explanations: const [
            ExplainEntry(
              metricId: 'cyclomatic-complexity',
              rationale: 'Why CC matters.',
              refactorHints: ['Extract helpers.'],
            ),
          ],
        ),
        sink,
      );
      await sink.close();
      final body = await temp.readAsString();
      expect(body, contains('## Explanations'));
      expect(body, contains('Why CC matters.'));
      expect(body, contains('Extract helpers.'));
    },
  );
}
