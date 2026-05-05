import 'package:analyzer/error/error.dart';

import '../../metrics/function/max_nesting_level.dart';
import '../../metrics/metric.dart';
import '_metric_rule_base.dart';

/// Reports a warning when a function or method's maximum nesting level
/// (deepest depth of `if`/`for`/`while`/`do`/`switch`/`try`/closure blocks)
/// reaches the configured threshold.
///
/// v0.1 behaviour: threshold baked at 4.
class MaximumNestingLevelRule extends FunctionMetricRule {
  MaximumNestingLevelRule()
    : super(
        name: 'dartrics_maximum_nesting_level',
        description: 'Function or method nesting depth exceeds the threshold.',
      );

  static const LintCode code = LintCode(
    'dartrics_maximum_nesting_level',
    "Maximum nesting level is {0}, which reaches dartrics's threshold of {1}.",
    correctionMessage:
        'Try inverting guard clauses or extracting nested blocks into helpers.',
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  FunctionMetric get metric => const MaxNestingLevel();

  @override
  num get threshold => 4;
}
