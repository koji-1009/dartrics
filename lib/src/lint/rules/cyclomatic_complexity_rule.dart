import 'package:analyzer/error/error.dart';

import '../../metrics/function/cyclomatic_complexity.dart';
import '../../metrics/metric.dart';
import '_metric_rule_base.dart';

/// Reports a warning when a function or method's cyclomatic complexity
/// (McCabe 1976) reaches the configured threshold.
///
/// v0.1 behaviour: threshold baked at 10. User-configurable thresholds are
/// future work.
class CyclomaticComplexityRule extends FunctionMetricRule {
  CyclomaticComplexityRule()
    : super(
        name: 'dartrics_cyclomatic_complexity',
        description:
            'Function or method cyclomatic complexity exceeds the threshold.',
      );

  static const LintCode code = LintCode(
    'dartrics_cyclomatic_complexity',
    "Cyclomatic complexity is {0}, which reaches dartrics's threshold of {1}.",
    correctionMessage:
        'Try splitting the function into smaller pieces or merging branches.',
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  FunctionMetric get metric => const CyclomaticComplexity();

  @override
  num get threshold => 10;
}
