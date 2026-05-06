import 'package:analyzer/error/error.dart';

import '../../metrics/function/number_of_parameters.dart';
import '../../metrics/metric.dart';
import 'metric_rule_base.dart';

/// Reports when a function, method, or constructor declares too many
/// formal parameters.
///
/// Default threshold is 4; override in `analysis_options.yaml`'s
/// `dartrics: { metrics: { number-of-parameters: { warning: <n> } } }`.
class NumberOfParametersRule extends FunctionMetricRule {
  NumberOfParametersRule()
    : super(
        name: 'dartrics_number_of_parameters',
        description: 'Number of formal parameters exceeds the threshold.',
      );

  static const LintCode code = LintCode(
    'dartrics_number_of_parameters',
    "Number of parameters is {0}, which reaches dartrics's threshold of {1}.",
    correctionMessage:
        'Try grouping related parameters into a class or named-parameter '
        'object.',
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  FunctionMetric get metric => const NumberOfParameters();

  @override
  num get defaultThreshold => 4;
}
