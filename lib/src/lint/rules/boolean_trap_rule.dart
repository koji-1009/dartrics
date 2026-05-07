import 'package:analyzer/error/error.dart';

import '../../metrics/function/boolean_trap.dart';
import '../../metrics/metric.dart';
import 'metric_rule_base.dart';

/// Reports when a function, method, or constructor declares two or more
/// **positional** `bool`-typed parameters — McConnell's *Code Complete*
/// and Bloch's *Effective Java* item 36 boolean-trap antipattern. At
/// the call site `foo(true, false, true)` forces every reader to jump
/// to the declaration to recover what each flag means; intent-named
/// methods, named parameters, or a typed enum read better. Named bool
/// parameters are intentionally not counted because the named call
/// site (`foo(animated: true)`) carries the intent on the spot.
///
/// Default threshold is 2; override in `analysis_options.yaml`'s
/// `dartrics: { metrics: { boolean-trap: { warning: <n> } } }`.
class BooleanTrapRule extends FunctionMetricRule {
  BooleanTrapRule()
    : super(
        name: 'dartrics_boolean_trap',
        description:
            'Function declares too many positional `bool` parameters '
            '(boolean-trap antipattern).',
      );

  static const LintCode code = LintCode(
    'dartrics_boolean_trap',
    'Function declares {0} positional `bool` parameters, which reaches '
        'dartrics\'s threshold of {1}; consider promoting them to named '
        'parameters, splitting into intent-named methods, or replacing '
        'the flags with a typed enum.',
    correctionMessage:
        'Promote the bool flags to named parameters (`foo({required '
        'bool show})`), split into separately named methods (`show()` '
        '/ `hide()`), or replace the flags with a typed enum.',
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  FunctionMetric get metric => const BooleanTrap();

  @override
  num get defaultThreshold => 2;
}
