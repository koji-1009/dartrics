import 'package:dartrics/src/models/analysis_report.dart';
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
}
