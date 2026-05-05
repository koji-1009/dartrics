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
/// Reference: P. Oman & J. Hagemeister, *Metrics for assessing a software
/// system's maintainability*, ICSM 1992.
class MaintainabilityIndex implements FunctionMetric {
  const MaintainabilityIndex();

  @override
  String get id => 'maintainability-index';

  @override
  num compute(FunctionMetricInput input) {
    final body = input.body;
    if (body == null) return 171;
    final volume = HalsteadCounts.fromBody(body).volume;
    final cc = const CyclomaticComplexity().compute(input);
    final loc = const MethodLength().compute(input);
    if (volume <= 0 || loc <= 0) return 171;
    final mi = 171 - 5.2 * math.log(volume) - 0.23 * cc - 16.2 * math.log(loc);
    return mi.clamp(0, 171);
  }
}
