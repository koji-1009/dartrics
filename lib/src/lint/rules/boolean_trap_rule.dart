import 'package:analyzer/error/error.dart';

import '../../metrics/function/boolean_trap.dart';
import '../../metrics/metric.dart';
import 'metric_rule_base.dart';

/// Reports when a function, method, or constructor declares two or more
/// `bool`-typed parameters — McConnell's *Code Complete* and Bloch's
/// *Effective Java* item 36 boolean-trap antipattern. At the call site
/// `foo(true, false, true)` forces every reader to jump to the
/// declaration to recover what each flag means; intent-named methods or
/// a typed enum read better.
///
/// Default threshold is 2; override in `analysis_options.yaml`'s
/// `dartrics: { metrics: { boolean-trap: { warning: <n> } } }`.
class BooleanTrapRule extends FunctionMetricRule {
  BooleanTrapRule()
    : super(
        name: 'dartrics_boolean_trap',
        description:
            'Function declares too many `bool` parameters '
            '(boolean-trap antipattern).',
      );

  static const LintCode code = LintCode(
    'dartrics_boolean_trap',
    'Function declares {0} `bool` parameters, which reaches dartrics\'s '
        'threshold of {1}; consider splitting into intent-named methods or '
        'replacing the flags with a typed enum.',
    correctionMessage:
        'Split into separately named methods (`show()` / `hide()`), '
        'replace the flags with a typed enum, or promote an "options" '
        'record so the call site reads as named fields.',
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  FunctionMetric get metric => const BooleanTrap();

  @override
  num get defaultThreshold => 2;
}
