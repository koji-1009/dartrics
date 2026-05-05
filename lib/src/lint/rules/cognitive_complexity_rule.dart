import 'package:analyzer/error/error.dart';

import '../../metrics/function/cognitive_complexity.dart';
import '../../metrics/metric.dart';
import '_metric_rule_base.dart';

/// Reports a warning when a function or method's cognitive complexity
/// (G. Ann Campbell, SonarSource 2018) reaches the configured threshold.
///
/// v0.1 behaviour: threshold baked at 15.
class CognitiveComplexityRule extends FunctionMetricRule {
  CognitiveComplexityRule()
    : super(
        name: 'dartrics_cognitive_complexity',
        description:
            'Function or method cognitive complexity exceeds the threshold.',
      );

  static const LintCode code = LintCode(
    'dartrics_cognitive_complexity',
    "Cognitive complexity is {0}, which reaches dartrics's threshold of {1}.",
    correctionMessage:
        'Try flattening nested control flow or extracting helpers.',
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  FunctionMetric get metric => const CognitiveComplexity();

  @override
  num get threshold => 15;
}
