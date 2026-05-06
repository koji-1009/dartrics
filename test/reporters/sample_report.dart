import 'package:dartrics/src/models/analysis_report.dart';
import 'package:dartrics/src/models/source_location.dart';
import 'package:dartrics/src/models/unused_declaration.dart';

/// Builds a small [AnalysisReport] containing one metric record with a
/// warning violation and one unused declaration. Useful as a shared fixture
/// for reporter tests.
AnalysisReport buildSampleReport() {
  const metricRecord = MetricRecord(
    file: '/proj/lib/foo.dart',
    scope: ScopeRef(
      kind: ScopeKind.method,
      name: 'Foo.bar',
      location: SourceLocation(path: '/proj/lib/foo.dart', line: 42, column: 3),
    ),
    values: {'cyclomatic-complexity': 12, 'cognitive-complexity': 18},
    violations: [
      MetricViolation(
        metricId: 'cyclomatic-complexity',
        severity: Severity.warning,
        threshold: 10,
      ),
    ],
  );
  const unused = UnusedDeclaration(
    kind: UnusedKind.function,
    name: '_legacyFormatter',
    location: SourceLocation(path: '/proj/lib/util.dart', line: 88, column: 1),
  );
  return AnalysisReport(
    version: '1.0',
    metrics: [metricRecord],
    unused: [unused],
  )..attachAnalyzedFileCount(2);
}
