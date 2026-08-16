import 'dart:io';

import 'package:dartrics/src/dismiss/dismissal.dart';
import 'package:dartrics/src/models/analysis_report.dart';
import 'package:dartrics/src/models/call_graph_signal.dart';
import 'package:dartrics/src/models/source_location.dart';
import 'package:dartrics/src/models/unused_declaration.dart';
import 'package:dartrics/src/reporters/ai_reporter.dart';
import 'package:test/test.dart';

import 'sample_report.dart';

void main() {
  test(
    'empty report emits a clean header (no `null` prefix from dapper)',
    () async {
      // dapper.formatYaml('# header only\n') returns 'null# header only\n'
      // because the document has no parseable body. The reporter sidesteps
      // that path so a clean codebase doesn't produce corrupted YAML.
      final tmp = Directory.systemTemp.createTempSync();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final temp = File('${tmp.path}/empty.yaml');
      final sink = temp.openWrite();
      AiReporter().report(
        AnalysisReport(version: '1.0', metrics: const [], unused: const []),
        sink,
      );
      await sink.close();
      final body = await temp.readAsString();
      expect(body, isNot(startsWith('null')));
      expect(body.trim(), '# dartrics ai-report v1');
    },
  );

  test('emits snapshot block when a diff filter is active', () async {
    final tmp = Directory.systemTemp.createTempSync();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final temp = File('${tmp.path}/ai.yaml');
    final sink = temp.openWrite();
    AiReporter().report(
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
    expect(body, contains('snapshot:'));
    expect(body, contains('mode: cache'));
    expect(body, contains('changedFiles: 0 of 3'));
  });

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

  test('counts block reports per-section entry totals', () async {
    // The four sections all start entries with the same `  - file:`
    // shape, so agents that grep to count violations over-count by the
    // other sections' entries. `counts:` is the one place that holds
    // the per-section totals.
    final tmp = Directory.systemTemp.createTempSync();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final temp = File('${tmp.path}/ai.yaml');
    final sink = temp.openWrite();
    final report = buildSampleReport();
    AiReporter(
      sourceLoader: (path) => {
        path: List.generate(100, (i) => 'line${i + 1}').join('\n'),
      },
    ).report(report, sink);
    await sink.close();
    final body = await temp.readAsString();
    expect(body, contains('counts:'));
    expect(body, contains('violations: 1'));
    expect(body, contains('unused: 1'));
    expect(body, contains('staleDismissals: 0'));
    expect(body, contains('signals: 0'));
    // counts precedes every section so agents see it before the entries.
    expect(body.indexOf('counts:'), lessThan(body.indexOf('violations:')));
  });

  test('counts reflects kept entries under --limit, not totals', () async {
    final tmp = Directory.systemTemp.createTempSync();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final temp = File('${tmp.path}/ai.yaml');
    final sink = temp.openWrite();
    final signals = <CallGraphSignal>[
      for (var i = 0; i < 5; i++)
        CallGraphSignal(
          file: 'lib/foo$i.dart',
          scope: ScopeRef(
            kind: ScopeKind.function,
            name: 'foo$i',
            location: SourceLocation(
              path: 'lib/foo$i.dart',
              line: 1,
              column: 1,
            ),
          ),
          fanInCallers: 5 - i,
          fanInCalls: 5 - i,
          fanOutCallees: 0,
          fanOutCalls: 0,
        ),
    ];
    AiReporter(limit: 2).report(
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
    // counts holds what this report includes (2); truncated holds the
    // dropped tail (3); the section total is their sum.
    expect(body, contains('counts:'));
    expect(body, contains('signals: 2'));
    expect(body, contains('truncated:'));
    expect(body, contains('signals: 3'));
  });

  test('counts block appears alongside a snapshot-only report', () async {
    // A --since run with zero findings still carries explicit zero
    // counts so "nothing fired in the changed set" is machine-readable.
    final tmp = Directory.systemTemp.createTempSync();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final temp = File('${tmp.path}/ai.yaml');
    final sink = temp.openWrite();
    AiReporter().report(
      AnalysisReport(
        version: '1.1',
        metrics: const [],
        unused: const [],
        snapshotMode: 'none',
        changedFileCount: 2,
      )..attachAnalyzedFileCount(3),
      sink,
    );
    await sink.close();
    final body = await temp.readAsString();
    expect(body, contains('counts:'));
    expect(body, contains('violations: 0'));
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
              complexityJustifiedBy: 'branch',
              complexityJustifiedThreshold: 0.8,
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
    expect(body, contains('complexityJustifiedBy: branch'));
    // dapper's YAML formatter normalises numeric scalars and trims
    // the trailing zero from `0.80` ⇒ `0.8`. We surfaced 0.80 from
    // the engine; either rendering is correct.
    expect(
      body,
      anyOf(
        contains('complexityJustifiedThreshold: 0.80'),
        contains('complexityJustifiedThreshold: 0.8'),
      ),
    );
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

  test('renders dismiss metadata and pushes dismissed entries last', () async {
    final tmp = Directory.systemTemp.createTempSync();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final temp = File('${tmp.path}/ai.yaml');
    final sink = temp.openWrite();
    final at = DateTime.utc(2026, 5, 6, 19, 14);
    final report = AnalysisReport(
      version: '1.0',
      metrics: [
        // Plain warning — should sort first.
        const MetricRecord(
          file: '/proj/live.dart',
          scope: ScopeRef(
            kind: ScopeKind.function,
            name: 'live',
            location: SourceLocation(
              path: '/proj/live.dart',
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
        // Dismissed warning — should sink to the bottom.
        MetricRecord(
          file: '/proj/dismissed.dart',
          scope: const ScopeRef(
            kind: ScopeKind.function,
            name: 'silenced',
            location: SourceLocation(
              path: '/proj/dismissed.dart',
              line: 1,
              column: 1,
            ),
          ),
          values: const {'cyclomatic-complexity': 11},
          violations: [
            MetricViolation(
              metricId: 'cyclomatic-complexity',
              severity: Severity.warning,
              threshold: 10,
              dismissed: true,
              dismissReason: 'state machine: splits hide intent',
              dismissedBy: 'claude-opus-4-7',
              dismissedAt: at,
              dismissedFrom: DismissalSource.yaml,
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
    expect(body, contains('dismissed: true'));
    expect(body, contains('dismissedFrom: yaml'));
    expect(body, contains('dismissedBy: claude-opus-4-7'));
    expect(body, contains('dismissedAt:'));
    expect(body, contains('"state machine: splits hide intent"'));
    final liveIdx = body.indexOf('live');
    final silencedIdx = body.indexOf('silenced');
    expect(liveIdx, lessThan(silencedIdx));
  });

  test('renders dismissalRejected without dismissed flag', () async {
    final tmp = Directory.systemTemp.createTempSync();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final temp = File('${tmp.path}/ai.yaml');
    final sink = temp.openWrite();
    final report = AnalysisReport(
      version: '1.0',
      metrics: const [
        MetricRecord(
          file: '/proj/foo.dart',
          scope: ScopeRef(
            kind: ScopeKind.function,
            name: 'fn',
            location: SourceLocation(
              path: '/proj/foo.dart',
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
      unused: [],
    );
    AiReporter(
      sourceLoader: (path) => {
        path: List.generate(100, (i) => 'line${i + 1}').join('\n'),
      },
    ).report(report, sink);
    await sink.close();
    final body = await temp.readAsString();
    expect(body, contains('dismissalRejected:'));
    expect(body, isNot(contains('dismissed: true')));
  });

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
          references: ['Author (1976). Title.'],
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
    expect(body, contains('references:'));
    expect(body, contains('Author (1976). Title.'));
  });

  test(
    'emits staleDismissals block when the report carries stale entries',
    () async {
      final tmp = Directory.systemTemp.createTempSync();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final temp = File('${tmp.path}/ai.yaml');
      final sink = temp.openWrite();
      AiReporter().report(
        AnalysisReport(
          version: '1.0',
          metrics: const [],
          unused: const [],
          staleDismissals: const [
            StaleDismissal(
              file: 'lib/foo.dart',
              scope: 'gone',
              metricId: 'cyclomatic-complexity',
              source: DismissalSource.yaml,
              reason: 'scope was renamed; entry is left over',
            ),
            StaleDismissal(
              file: 'lib/bar.dart',
              scope: 'alsoGone',
              metricId: 'method-length',
              source: DismissalSource.comment,
            ),
          ],
        ),
        sink,
      );
      await sink.close();

      final body = await temp.readAsString();
      expect(body, contains('staleDismissals:'));
      expect(body, contains('file: lib/foo.dart'));
      expect(body, contains('scope: gone'));
      expect(body, contains('metric: cyclomatic-complexity'));
      expect(body, contains('source: yaml'));
      expect(body, contains('source: comment'));
      expect(body, contains('renamed'));
    },
  );

  test('snippet with first line deeper than later lines round-trips through dapper', () async {
    // Regression: a violation centred on a method-body line followed
    // by a closing brace at column 0 produces a YAML literal block
    // whose first content line is more indented than later lines.
    // YAML auto-detect (`|`) latches onto the first line's indent and
    // treats the dedented closer as the next mapping key, which made
    // dapper's `formatYaml` re-parse pass abort with `Expected a key
    // while parsing a block mapping`. The reporter now pins the
    // block scalar to `|2` so the parser uses an absolute baseline
    // and tolerates dedenting content lines.
    final tmp = Directory.systemTemp.createTempSync();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final temp = File('${tmp.path}/ai.yaml');
    final sink = temp.openWrite();
    // Centre line 4 means the snippet covers lines 1–7. Line 4 is
    // four spaces in — deeper than the closing braces on lines 5–7.
    const source =
        'class C {\n'
        '  void foo() {\n'
        '    if (x) {\n'
        '      bar();\n'
        '    }\n'
        '  }\n'
        '}\n';
    AiReporter(sourceLoader: (path) => {path: source}).report(
      AnalysisReport(
        version: '1.0',
        metrics: const [
          MetricRecord(
            file: '/proj/lib/foo.dart',
            scope: ScopeRef(
              kind: ScopeKind.method,
              name: 'C.foo',
              location: SourceLocation(
                path: '/proj/lib/foo.dart',
                line: 4,
                column: 7,
              ),
            ),
            values: {'cyclomatic-complexity': 12},
            violations: [
              MetricViolation(
                metricId: 'cyclomatic-complexity',
                severity: Severity.warning,
                threshold: 10,
              ),
            ],
          ),
        ],
        unused: const [],
      ),
      sink,
    );
    await sink.close();
    // The crash path was an exception thrown inside dapper's
    // formatYaml; reaching this assertion at all means the round-trip
    // succeeded. Spot-check the output for the closing-brace lines
    // that previously triggered the parser bail.
    final body = await temp.readAsString();
    expect(body, contains('# dartrics ai-report v1'));
    expect(body, contains('snippet:'));
    expect(body, contains('}'));
  });

  test('emits signals block with reference-only framing', () async {
    final tmp = Directory.systemTemp.createTempSync();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final temp = File('${tmp.path}/ai.yaml');
    final sink = temp.openWrite();
    AiReporter().report(
      AnalysisReport(
        version: '1.1',
        metrics: const [],
        unused: const [],
        signals: const [
          CallGraphSignal(
            file: 'lib/foo.dart',
            scope: ScopeRef(
              kind: ScopeKind.method,
              name: 'Foo.bar',
              location: SourceLocation(
                path: 'lib/foo.dart',
                line: 7,
                column: 1,
              ),
            ),
            fanInCallers: 4,
            fanInCalls: 11,
            fanOutCallees: 2,
            fanOutCalls: 3,
          ),
        ],
      ),
      sink,
    );
    await sink.close();
    final body = await temp.readAsString();
    expect(body, contains('signals:'));
    // The framing comments are the load-bearing part of the section —
    // they're what tells the AI loop "compare against intent, don't
    // treat as a verdict."
    expect(body, contains('NOT verdicts'));
    expect(body, contains('fanInCallers: 4'));
    expect(body, contains('fanOutCallees: 2'));
  });

  test(
    'unused block carries deletion-or-unwired framing as YAML comments',
    () async {
      final tmp = Directory.systemTemp.createTempSync();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final temp = File('${tmp.path}/ai.yaml');
      final sink = temp.openWrite();
      AiReporter().report(
        AnalysisReport(
          version: '1.1',
          metrics: const [],
          unused: const [
            UnusedDeclaration(
              kind: UnusedKind.function,
              name: 'orphan',
              location: SourceLocation(path: 'lib/x.dart', line: 3, column: 1),
            ),
          ],
        ),
        sink,
      );
      await sink.close();
      final body = await temp.readAsString();
      expect(body, contains('unused:'));
      expect(body, contains('unwired'));
    },
  );

  test(
    'signals tie-breaker falls through to fanOutCallees when fan-in is equal',
    () async {
      final tmp = Directory.systemTemp.createTempSync();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final temp = File('${tmp.path}/ai.yaml');
      final sink = temp.openWrite();
      AiReporter().report(
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
                location: SourceLocation(
                  path: 'lib/lo.dart',
                  line: 1,
                  column: 1,
                ),
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
                location: SourceLocation(
                  path: 'lib/hi.dart',
                  line: 1,
                  column: 1,
                ),
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
      final hiIdx = body.indexOf('scope: hi');
      final loIdx = body.indexOf('scope: lo');
      expect(hiIdx >= 0 && loIdx >= 0, isTrue);
      // Tie on fanInCallers → comparator falls through to
      // fanOutCallees, so `hi` (5) must come before `lo` (1).
      expect(hiIdx, lessThan(loIdx));
    },
  );

  test(
    'signals dropped by --limit are summarised in truncated block',
    () async {
      final tmp = Directory.systemTemp.createTempSync();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final temp = File('${tmp.path}/ai.yaml');
      final sink = temp.openWrite();
      final signals = <CallGraphSignal>[
        for (var i = 0; i < 5; i++)
          CallGraphSignal(
            file: 'lib/foo$i.dart',
            scope: ScopeRef(
              kind: ScopeKind.function,
              name: 'foo$i',
              location: SourceLocation(
                path: 'lib/foo$i.dart',
                line: 1,
                column: 1,
              ),
            ),
            fanInCallers: 5 - i,
            fanInCalls: 5 - i,
            fanOutCallees: 0,
            fanOutCalls: 0,
          ),
      ];
      AiReporter(limit: 2).report(
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
      expect(body, contains('truncated:'));
      expect(body, contains('signals: 3'));
    },
  );
}
