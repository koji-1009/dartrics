import 'dart:math' as math;

import '../metric.dart';
import 'cyclomatic_complexity.dart';
import 'halstead.dart';
import 'method_length.dart';

/// Maintainability Index (Oman, 1992) — `171 - 5.2·ln(V) - 0.23·CC - 16.2·ln(LOC)`.
///
/// Higher values indicate code that is easier to maintain. The original
/// formula returns a value typically in `[0, 171]`; we clamp to that range
/// to avoid surprising negatives on tiny synthetic bodies.
///
/// Off by default: Microsoft's Visual Studio team retired the metric from
/// recommended UI in newer releases, citing its composite-of-CC-and-Volume
/// nature as opaque to act on. Opt in via
/// `dartrics: { metrics: { maintainability-index: { enabled: true } } }`.
///
/// Reference: P. Oman & J. Hagemeister, *Metrics for assessing a software
/// system's maintainability*, ICSM 1992.
class MaintainabilityIndex extends FunctionMetric {
  const MaintainabilityIndex();

  @override
  String get id => 'maintainability-index';

  @override
  bool get defaultEnabled => false;

  @override
  MetricPolarity get polarity => MetricPolarity.up;

  @override
  String get rationale =>
      'Maintainability Index `MI = 171 − 5.2·ln(V) − 0.23·CC − '
      '16.2·ln(LOC)` (Oman & Hagemeister, ICSM 1992) summarises three '
      'orthogonal signals — Halstead Volume, Cyclomatic Complexity, '
      'and method length — into a single 0–171 score. Off by default '
      'because Microsoft retired it from the recommended Visual Studio '
      'UI in 2017, citing that its composite nature makes it opaque '
      'to act on; opt in if you want the legacy single-number summary.';

  @override
  List<String> get refactorHints => const [
    'Treat MI as an alarm only — when it drops, look at CC, SLOC, and Halstead individually for the actionable signal.',
    'Split very long methods first; LOC enters logarithmically and has the largest swing of the three components.',
  ];

  @override
  num compute(FunctionMetricInput input) {
    final volume = HalsteadCounts.fromBody(input.body).volume;
    final cc = const CyclomaticComplexity().compute(input);
    final loc = const MethodLength().compute(input);
    if (volume <= 0 || loc <= 0) return 171;
    final mi = 171 - 5.2 * math.log(volume) - 0.23 * cc - 16.2 * math.log(loc);
    return mi.clamp(0, 171);
  }
}
