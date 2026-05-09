// Smoke test that imports every function-level metric calculator
// through the *public* dartrics.dart entrypoint. If a new function
// metric is added under lib/src/metrics/function/ but not re-exported
// from lib/dartrics.dart, this file will fail to compile — surfacing
// the omission before release.
//
// Class- and library-level metrics, report / regression / coverage /
// dismissal / unused-detector shapes, and the engine are intentionally
// CLI-only. The supported integration point for those is
// `dartrics analyze --reporter json`.

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
    ];
    final ids = metrics.map((m) => m.id).toSet();
    // Each calculator declares a unique id.
    expect(ids, hasLength(metrics.length));
    // Pin BooleanTrap explicitly so a future export-drop is caught
    // even if the list shape changes.
    expect(ids, contains('boolean-trap'));
  });

  test('FunctionMetric polarity enum values are reachable', () {
    expect(MetricPolarity.down.name, 'down');
    expect(MetricPolarity.neutral.name, 'neutral');
    expect(const HalsteadVolume().polarity, MetricPolarity.neutral);
  });

  test('dartricsVersion is a non-empty semver-like string', () {
    expect(dartricsVersion, isNotEmpty);
    expect(dartricsVersion, matches(RegExp(r'^\d+\.\d+\.\d+')));
  });
}
