// Smoke test that imports every function-level metric calculator
// through the *public* dartrics.dart entrypoint. If a new function
// metric is added under lib/src/metrics/function/ but not re-exported
// from lib/dartrics.dart, this file will fail to compile — surfacing
// the omission before release.
//
// Class- and library-level metrics, report / regression / coverage /
// dismissal / unused-detector shapes, and the engine are intentionally
// CLI-only in 0.1.0. The supported integration point for those is
// `dartrics analyze --reporter json`. If a future need surfaces a
// Dart-level handle, this surface gets expanded — never narrowed.

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
    // BooleanTrap was the most recent addition; pin it explicitly so a
    // future export-drop is caught even if the list shape changes.
    expect(ids, contains('boolean-trap'));
  });

  test('FunctionMetric polarity enum values are reachable', () {
    // MetricPolarity.up has no built-in metric in 0.1.0 (the
    // maintainability index was retired). The enum value stays
    // exported so custom embedder metrics can register with up
    // polarity; the regression-diff and doctor up-polarity branches
    // are tested directly via their public helpers.
    expect(MetricPolarity.down.name, 'down');
    expect(MetricPolarity.up.name, 'up');
    expect(MetricPolarity.neutral.name, 'neutral');
    expect(const HalsteadVolume().polarity, MetricPolarity.neutral);
  });

  test('dartricsVersion is a non-empty semver-like string', () {
    expect(dartricsVersion, isNotEmpty);
    expect(dartricsVersion, matches(RegExp(r'^\d+\.\d+\.\d+')));
  });
}
