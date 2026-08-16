import 'dart:io';

import 'package:dartrics/src/dismiss/dismissal.dart';
import 'package:dartrics/src/models/analysis_report.dart';
import 'package:dartrics/src/models/call_graph_signal.dart';
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
    expect(body, contains('snapshot mode'));
  });

  test(
    'summary surfaces snapshot diff filter with `no new findings` hint',
    () async {
      final temp = await File.fromUri(
        Uri.file('${Directory.systemTemp.createTempSync().path}/r.md'),
      ).create();
      final sink = temp.openWrite();
      MdReporter().report(
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

      final body = await temp.readAsString();
      expect(body, contains('snapshot mode'));
      expect(body, contains('cache'));
      expect(body, contains('files changed'));
      expect(body, contains('0 of 3'));
      expect(body, contains('no new findings'));
    },
  );

  test(
    'summary omits `no new findings` hint when some files changed',
    () async {
      final temp = await File.fromUri(
        Uri.file('${Directory.systemTemp.createTempSync().path}/r.md'),
      ).create();
      final sink = temp.openWrite();
      MdReporter().report(
        AnalysisReport(
          version: '1.0',
          metrics: const [],
          unused: const [],
          snapshotMode: 'cache',
          changedFileCount: 2,
        )..attachAnalyzedFileCount(3),
        sink,
      );
      await sink.close();

      final body = await temp.readAsString();
      expect(body, contains('2 of 3'));
      expect(body, isNot(contains('no new findings')));
    },
  );

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
    'renders a Signals (reference) section with framing and a top-N table',
    () async {
      final temp = await File.fromUri(
        Uri.file('${Directory.systemTemp.createTempSync().path}/r.md'),
      ).create();
      final sink = temp.openWrite();
      final signals = <CallGraphSignal>[
        for (var i = 0; i < 12; i++)
          CallGraphSignal(
            file: 'lib/foo$i.dart',
            scope: ScopeRef(
              kind: ScopeKind.method,
              name: 'Foo$i.bar',
              location: SourceLocation(
                path: 'lib/foo$i.dart',
                line: 1 + i,
                column: 1,
              ),
            ),
            fanInCallers: 12 - i,
            fanInCalls: (12 - i) * 2,
            fanOutCallees: 3,
            fanOutCalls: 5,
          ),
      ];
      MdReporter().report(
        AnalysisReport(
          version: '1.1',
          metrics: const [],
          unused: const [],
          signals: signals,
        ),
        sink,
      );
      await sink.close();
      final body = await temp.readAsString();
      expect(body, contains('## Signals (reference)'));
      expect(body, contains('not verdicts'));
      // top-N capped at 10; the rest land in a follow-up note
      expect(body, contains('Foo0.bar'));
      expect(body, contains('Foo9.bar'));
      expect(body, isNot(contains('Foo11.bar')));
      expect(body, contains('+ 2 more signal'));
    },
  );

  test('Signals table tie-breaker falls through to fanOutCallees when fan-in is equal', () async {
    final temp = await File.fromUri(
      Uri.file('${Directory.systemTemp.createTempSync().path}/r.md'),
    ).create();
    final sink = temp.openWrite();
    MdReporter().report(
      AnalysisReport(
        version: '1.1',
        metrics: const [],
        unused: const [],
        signals: const [
          CallGraphSignal(
            file: 'lib/lo.dart',
            scope: ScopeRef(
              kind: ScopeKind.function,
              name: 'lo',
              location: SourceLocation(path: 'lib/lo.dart', line: 1, column: 1),
            ),
            fanInCallers: 3,
            fanInCalls: 3,
            fanOutCallees: 1,
            fanOutCalls: 1,
          ),
          CallGraphSignal(
            file: 'lib/hi.dart',
            scope: ScopeRef(
              kind: ScopeKind.function,
              name: 'hi',
              location: SourceLocation(path: 'lib/hi.dart', line: 1, column: 1),
            ),
            fanInCallers: 3,
            fanInCalls: 3,
            fanOutCallees: 5,
            fanOutCalls: 5,
          ),
        ],
      ),
      sink,
    );
    await sink.close();
    final body = await temp.readAsString();
    expect(body.indexOf('`hi`'), lessThan(body.indexOf('`lo`')));
  });

  test('omits the Signals section when no signals are present', () async {
    final temp = await File.fromUri(
      Uri.file('${Directory.systemTemp.createTempSync().path}/r.md'),
    ).create();
    final sink = temp.openWrite();
    MdReporter().report(buildSampleReport(), sink);
    await sink.close();
    final body = await temp.readAsString();
    expect(body, isNot(contains('## Signals')));
  });

  test(
    'reframes Unused Declarations with deletion-or-unwired guidance',
    () async {
      final temp = await File.fromUri(
        Uri.file('${Directory.systemTemp.createTempSync().path}/r.md'),
      ).create();
      final sink = temp.openWrite();
      MdReporter().report(buildSampleReport(), sink);
      await sink.close();
      final body = await temp.readAsString();
      expect(body, contains('## Unused Declarations'));
      expect(body, contains('unwired'));
    },
  );

  test(
    'renders a Stale Dismissals section listing reason + source when present',
    () async {
      final temp = await File.fromUri(
        Uri.file('${Directory.systemTemp.createTempSync().path}/r.md'),
      ).create();
      final sink = temp.openWrite();
      final report = AnalysisReport(
        version: '1.1',
        metrics: const [],
        unused: const [],
        staleDismissals: const [
          StaleDismissal(
            file: 'lib/foo.dart',
            scope: 'Foo.bar',
            metricId: 'cyclomatic-complexity',
            source: DismissalSource.yaml,
            reason: 'state machine: splits hide intent',
          ),
          StaleDismissal(
            file: 'lib/baz.dart',
            scope: 'Baz.qux',
            metricId: 'cognitive-complexity',
            source: DismissalSource.comment,
          ),
        ],
      );
      MdReporter().report(report, sink);
      await sink.close();
      final body = await temp.readAsString();
      expect(body, contains('## Stale Dismissals'));
      expect(body, contains('lib/foo.dart'));
      expect(body, contains('Foo.bar'));
      expect(body, contains('cyclomatic-complexity'));
      expect(body, contains('yaml'));
      expect(body, contains('state machine: splits hide intent'));
      expect(body, contains('lib/baz.dart'));
      expect(body, contains('comment'));
    },
  );

  test(
    'omits the Stale Dismissals section when no stale entries are present',
    () async {
      final temp = await File.fromUri(
        Uri.file('${Directory.systemTemp.createTempSync().path}/r.md'),
      ).create();
      final sink = temp.openWrite();
      MdReporter().report(buildSampleReport(), sink);
      await sink.close();
      final body = await temp.readAsString();
      expect(body, isNot(contains('## Stale Dismissals')));
    },
  );

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
              references: ['Author (1976). Title.'],
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
      expect(body, contains('**References:**'));
      expect(body, contains('Author (1976). Title.'));
    },
  );
}
