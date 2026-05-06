import '../metric.dart';

/// Number of formal parameters declared by the function (positional + named,
/// optional included). Member-initializer parameters of constructors are
/// counted alongside regular ones since they are still visible at the call
/// site.
class NumberOfParameters extends FunctionMetric {
  const NumberOfParameters();

  @override
  String get id => 'number-of-parameters';

  @override
  num compute(FunctionMetricInput input) {
    return input.parameters?.parameters.length ?? 0;
  }
}
