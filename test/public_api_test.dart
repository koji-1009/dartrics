// Smoke test that imports every function-level metric calculator
// through the *public* dartrics.dart entrypoint. If a new function
// metric is added under lib/src/metrics/function/ but not re-exported
// from lib/dartrics.dart, this file will fail to compile — surfacing
// the omission before release.
//
// Class- and library-level metrics are intentionally CLI-only in 0.1.0
// (see README "Embedding"), so this file does not exercise them.

import 'package:dartrics/dartrics.dart';
import 'package:test/test.dart';

void main() {
  test('every default function-level metric is reachable via public API', () {
    final metrics = <FunctionMetric>[
      const CyclomaticComplexity(),
      const CognitiveComplexity(),
      const MaxNestingLevel(),
      const NumberOfParameters(),
      const BooleanTrap(),
      const MethodLength(),
      const SourceLinesOfCode(),
      const HalsteadVolume(),
      const HalsteadDifficulty(),
      const HalsteadEffort(),
      const MaintainabilityIndex(),
    ];
    final ids = metrics.map((m) => m.id).toSet();
    // Each calculator declares a unique id.
    expect(ids, hasLength(metrics.length));
    // BooleanTrap is the most recent addition; pin it explicitly so a
    // future export-drop is caught even if the list shape changes.
    expect(ids, contains('boolean-trap'));
  });

  test('report shapes round-trip through the public API surface', () {
    // Touch the report-shape exports so removing one trips compilation.
    const violation = MetricViolation(
      id: 'a3f1c4e9b2d70218',
      metricId: 'cyclomatic-complexity',
      severity: Severity.warning,
      threshold: 10,
    );
    expect(violation.id, 'a3f1c4e9b2d70218');
    expect(MetricPolarity.down.name, 'down');
    expect(ScopeKind.function.name, 'function');
    expect(ChangeDirection.improved.name, 'improved');
    expect(DismissalSource.yaml.name, 'yaml');
  });
}
