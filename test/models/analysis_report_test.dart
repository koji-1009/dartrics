import 'package:dartrics/src/dismiss/dismissal.dart';
import 'package:dartrics/src/models/analysis_report.dart';
import 'package:dartrics/src/models/call_graph_signal.dart';
import 'package:dartrics/src/models/source_location.dart';
import 'package:dartrics/src/models/unused_declaration.dart';
import 'package:test/test.dart';

void main() {
  test('toJson round-trips via stable schema keys', () {
    final report = AnalysisReport(
      version: '1.0',
      metrics: const [
        MetricRecord(
          file: 'a.dart',
          scope: ScopeRef(
            kind: ScopeKind.method,
            name: 'A.b',
            location: SourceLocation(path: 'a.dart', line: 5, column: 1),
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
      unused: const [
        UnusedDeclaration(
          kind: UnusedKind.function,
          name: 'orphan',
          location: SourceLocation(path: 'b.dart', line: 2, column: 1),
        ),
      ],
    )..attachAnalyzedFileCount(3);

    final json = report.toJson();
    expect(json['version'], '1.0');
    expect(report.analyzedFileCount, 3);

    final metricsJson = (json['metrics']! as List).cast<Map<String, Object?>>();
    final scopeJson = metricsJson.first['scope']! as Map<String, Object?>;
    expect(scopeJson['type'], 'method');
    expect(scopeJson['name'], 'A.b');

    final violationsJson = (metricsJson.first['violations']! as List)
        .cast<Map<String, Object?>>();
    expect(violationsJson.first['metric'], 'cyclomatic-complexity');
    expect(violationsJson.first['level'], 'warning');

    final unusedJson = (json['unused']! as List).cast<Map<String, Object?>>();
    expect(unusedJson.first['kind'], 'function');
    expect(unusedJson.first['name'], 'orphan');
    expect(unusedJson.first['line'], 2);
  });

  test('hasSeverityAtLeast returns true at the worst encountered severity', () {
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
          values: {'cyclomatic-complexity': 30},
          violations: [
            MetricViolation(
              metricId: 'cyclomatic-complexity',
              severity: Severity.error,
              threshold: 20,
            ),
            MetricViolation(
              metricId: 'cognitive-complexity',
              severity: Severity.warning,
              threshold: 15,
            ),
          ],
        ),
      ],
      unused: const [],
    );
    expect(report.hasSeverityAtLeast(Severity.error), isTrue);
    expect(report.hasSeverityAtLeast(Severity.warning), isTrue);
  });

  test('hasSeverityAtLeast returns false when no violations exist', () {
    final report = AnalysisReport(
      version: '1.0',
      metrics: const [],
      unused: const [],
    );
    expect(report.hasSeverityAtLeast(Severity.warning), isFalse);
  });

  test('toJson emits explanations when present and omits when empty', () {
    final withExplanations = AnalysisReport(
      version: '1.1',
      metrics: const [],
      unused: const [],
      explanations: const [
        ExplainEntry(
          metricId: 'cyclomatic-complexity',
          rationale: 'High CC hides intent.',
          refactorHints: ['Extract guard clauses.'],
          references: ['McCabe (1976).'],
        ),
      ],
    );
    final json = withExplanations.toJson();
    expect(json.containsKey('explanations'), isTrue);
    final explanations = (json['explanations']! as List)
        .cast<Map<String, Object?>>();
    expect(explanations.first['metric'], 'cyclomatic-complexity');
    expect(explanations.first['rationale'], 'High CC hides intent.');
    expect(explanations.first['references'], ['McCabe (1976).']);

    final empty = AnalysisReport(
      version: '1.1',
      metrics: const [],
      unused: const [],
    );
    expect(empty.toJson().containsKey('explanations'), isFalse);
  });

  test('toJson emits staleDismissals when present and omits the references key '
      'on an ExplainEntry with no citations', () {
    final report = AnalysisReport(
      version: '1.1',
      metrics: const [],
      unused: const [],
      explanations: const [
        ExplainEntry(
          metricId: 'cognitive-complexity',
          rationale: 'Nested control flow is hard to follow.',
          refactorHints: ['Flatten with early returns.'],
        ),
      ],
      staleDismissals: const [
        StaleDismissal(
          file: 'lib/x.dart',
          scope: 'X.y',
          metricId: 'cyclomatic-complexity',
          source: DismissalSource.yaml,
          reason: 'state machine: splits hide intent',
        ),
      ],
    );
    final json = report.toJson();
    final explanations = (json['explanations']! as List)
        .cast<Map<String, Object?>>();
    expect(explanations.first.containsKey('references'), isFalse);

    final stale = (json['staleDismissals']! as List)
        .cast<Map<String, Object?>>();
    expect(stale.first['file'], 'lib/x.dart');
    expect(stale.first['scope'], 'X.y');
    expect(stale.first['metric'], 'cyclomatic-complexity');
    expect(stale.first['source'], 'yaml');
    expect(stale.first['reason'], 'state machine: splits hide intent');
  });

  test('toJson emits signals when present and omits when empty', () {
    final report = AnalysisReport(
      version: '1.1',
      metrics: const [],
      unused: const [],
      signals: const [
        CallGraphSignal(
          file: 'lib/foo.dart',
          scope: ScopeRef(
            kind: ScopeKind.method,
            name: 'Foo.bar',
            location: SourceLocation(path: 'lib/foo.dart', line: 7, column: 3),
          ),
          fanInCallers: 4,
          fanInCalls: 11,
          fanOutCallees: 2,
          fanOutCalls: 3,
        ),
      ],
    );
    final json = report.toJson();
    expect(json.containsKey('signals'), isTrue);
    final signals = (json['signals']! as List).cast<Map<String, Object?>>();
    expect(signals.first['file'], 'lib/foo.dart');
    expect(signals.first['fanInCallers'], 4);
    expect(signals.first['fanInCalls'], 11);
    expect(signals.first['fanOutCallees'], 2);
    expect(signals.first['fanOutCalls'], 3);
    final scope = signals.first['scope']! as Map<String, Object?>;
    expect(scope['name'], 'Foo.bar');

    final empty = AnalysisReport(
      version: '1.1',
      metrics: const [],
      unused: const [],
    );
    expect(empty.toJson().containsKey('signals'), isFalse);
  });
}
