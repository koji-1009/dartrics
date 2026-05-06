import 'dart:io';

import 'package:dartrics/src/models/analysis_report.dart';
import 'package:dartrics/src/models/source_location.dart';
import 'package:dartrics/src/reporters/ai_reporter.dart';
import 'package:test/test.dart';

import 'sample_report.dart';

void main() {
  test('emits violations and unused with snippet placeholder', () async {
    final tmp = Directory.systemTemp.createTempSync();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final temp = File('${tmp.path}/ai.yaml');
    final sink = temp.openWrite();
    AiReporter(
      sourceLoader: (path) => {
        path: List.generate(100, (i) => 'line${i + 1}').join('\n'),
      },
    ).report(buildSampleReport(), sink);
    await sink.close();

    final body = await temp.readAsString();
    expect(body, contains('dartrics ai-report v1'));
    expect(body, contains('violations:'));
    expect(body, contains('cyclomatic-complexity'));
    expect(body, contains('unused:'));
    expect(body, contains('_legacyFormatter'));
  });

  test('renders coverage and complexityJustified on violations', () async {
    final tmp = Directory.systemTemp.createTempSync();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final temp = File('${tmp.path}/ai.yaml');
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
              line: 42,
              column: 3,
            ),
          ),
          values: {'cyclomatic-complexity': 12},
          violations: [
            MetricViolation(
              metricId: 'cyclomatic-complexity',
              severity: Severity.warning,
              threshold: 10,
              scopeCoverage: 0.95,
              scopeBranchCoverage: 0.92,
              complexityJustified: true,
            ),
          ],
        ),
      ],
      unused: const [],
    );
    AiReporter(
      sourceLoader: (path) => {
        path: List.generate(100, (i) => 'line${i + 1}').join('\n'),
      },
    ).report(report, sink);
    await sink.close();
    final body = await temp.readAsString();
    expect(body, contains('coverage: 0.95'));
    expect(body, contains('branchCoverage: 0.92'));
    expect(body, contains('complexityJustified: true'));
  });

  test('orders uncovered errors before covered warnings', () async {
    final tmp = Directory.systemTemp.createTempSync();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final temp = File('${tmp.path}/ai.yaml');
    final sink = temp.openWrite();
    final report = AnalysisReport(
      version: '1.0',
      metrics: const [
        // Covered warning — should land below.
        MetricRecord(
          file: '/proj/a.dart',
          scope: ScopeRef(
            kind: ScopeKind.function,
            name: 'covered',
            location: SourceLocation(path: '/proj/a.dart', line: 10, column: 1),
          ),
          values: {'cyclomatic-complexity': 11},
          violations: [
            MetricViolation(
              metricId: 'cyclomatic-complexity',
              severity: Severity.warning,
              threshold: 10,
              scopeCoverage: 0.95,
              complexityJustified: true,
            ),
          ],
        ),
        // Uncovered error — should land first.
        MetricRecord(
          file: '/proj/b.dart',
          scope: ScopeRef(
            kind: ScopeKind.function,
            name: 'uncovered',
            location: SourceLocation(path: '/proj/b.dart', line: 20, column: 1),
          ),
          values: {'cyclomatic-complexity': 25},
          violations: [
            MetricViolation(
              metricId: 'cyclomatic-complexity',
              severity: Severity.error,
              threshold: 20,
              scopeCoverage: 0.10,
            ),
          ],
        ),
      ],
      unused: const [],
    );
    AiReporter(
      sourceLoader: (path) => {
        path: List.generate(100, (i) => 'line${i + 1}').join('\n'),
      },
    ).report(report, sink);
    await sink.close();
    final body = await temp.readAsString();
    final uncoveredIdx = body.indexOf('uncovered');
    final coveredIdx = body.indexOf('covered');
    expect(uncoveredIdx, isNonNegative);
    expect(uncoveredIdx, lessThan(coveredIdx));
  });

  test(
    'sort tie-breakers — coverage-aware ordering at the same severity',
    () async {
      final tmp = Directory.systemTemp.createTempSync();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final temp = File('${tmp.path}/ai.yaml');
      final sink = temp.openWrite();
      final report = AnalysisReport(
        version: '1.0',
        metrics: const [
          // Same severity (warning), no coverage data on either side, plus
          // one with coverage data and one with high coverage that becomes
          // justified — exercises every branch in _compareViolations.
          MetricRecord(
            file: '/proj/no_cov.dart',
            scope: ScopeRef(
              kind: ScopeKind.function,
              name: 'noCovA',
              location: SourceLocation(
                path: '/proj/no_cov.dart',
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
              ),
            ],
          ),
          MetricRecord(
            file: '/proj/no_cov.dart',
            scope: ScopeRef(
              kind: ScopeKind.function,
              name: 'noCovB',
              location: SourceLocation(
                path: '/proj/no_cov.dart',
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
              ),
            ],
          ),
          MetricRecord(
            file: '/proj/low_cov.dart',
            scope: ScopeRef(
              kind: ScopeKind.function,
              name: 'lowCov',
              location: SourceLocation(
                path: '/proj/low_cov.dart',
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
                scopeCoverage: 0.10,
              ),
            ],
          ),
          MetricRecord(
            file: '/proj/high_cov.dart',
            scope: ScopeRef(
              kind: ScopeKind.function,
              name: 'highCov',
              location: SourceLocation(
                path: '/proj/high_cov.dart',
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
                scopeCoverage: 0.99,
                complexityJustified: true,
              ),
            ],
          ),
        ],
        unused: const [],
      );
      AiReporter(
        sourceLoader: (path) => {
          path: List.generate(100, (i) => 'line${i + 1}').join('\n'),
        },
      ).report(report, sink);
      await sink.close();
      final body = await temp.readAsString();
      // Expected order at the same severity:
      //  lowCov (covered, low) → noCovA / noCovB (no coverage) → highCov (justified)
      final lowIdx = body.indexOf('lowCov');
      final noAIdx = body.indexOf('noCovA');
      final noBIdx = body.indexOf('noCovB');
      final highIdx = body.indexOf('highCov');
      expect(lowIdx, lessThan(noAIdx));
      expect(noAIdx, lessThan(highIdx));
      // The two no-coverage entries must remain present (relative order is
      // not contractually fixed; we only verify both appear between the
      // covered and the justified-high-coverage entries).
      expect(noBIdx, greaterThan(lowIdx));
      expect(noBIdx, lessThan(highIdx));
    },
  );

  test('renders an explain block when explanations are attached', () async {
    final tmp = Directory.systemTemp.createTempSync();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final temp = File('${tmp.path}/ai.yaml');
    final sink = temp.openWrite();
    final report = buildSampleReport(
      explanations: const [
        ExplainEntry(
          metricId: 'cyclomatic-complexity',
          rationale: 'Multi\nline rationale: with colon and # hash.',
          refactorHints: ['Plain hint.', 'Has: colon hint.'],
        ),
      ],
    );
    AiReporter(
      sourceLoader: (path) => {
        path: List.generate(100, (i) => 'line${i + 1}').join('\n'),
      },
    ).report(report, sink);
    await sink.close();

    final body = await temp.readAsString();
    expect(body, contains('explain:'));
    expect(body, contains('Multi'));
    expect(body, contains('"Has: colon hint."'));
  });
}
