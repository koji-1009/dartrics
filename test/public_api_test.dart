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
      const HalsteadDifficulty(),
      const HalsteadEffort(),
      const MaintainabilityIndex(),
    ];
    final ids = metrics.map((m) => m.id).toSet();
    // Each calculator declares a unique id.
    expect(ids, hasLength(metrics.length));
    // BooleanTrap was the most recent addition; pin it explicitly so a
    // future export-drop is caught even if the list shape changes.
    expect(ids, contains('boolean-trap'));
  });

  test('FunctionMetric polarity values are reachable', () {
    expect(MetricPolarity.down.name, 'down');
    expect(MetricPolarity.up.name, 'up');
    expect(MetricPolarity.neutral.name, 'neutral');
    // MaintainabilityIndex is the only "up" polarity metric in the
    // built-in catalogue; keep that pinned so polarity wiring doesn't
    // silently flip.
    expect(const MaintainabilityIndex().polarity, MetricPolarity.up);
  });

  test('dartricsVersion is a non-empty semver-like string', () {
    expect(dartricsVersion, isNotEmpty);
    expect(dartricsVersion, matches(RegExp(r'^\d+\.\d+\.\d+')));
  });
}
