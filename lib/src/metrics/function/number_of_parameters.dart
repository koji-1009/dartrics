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
  String get rationale =>
      'Number of parameters counts every formal parameter (positional + '
      'named, optional included; constructor `this.foo` initializers '
      'count too). Long parameter lists are one of the original "code '
      'smells" catalogued by Fowler in *Refactoring* (1999); they '
      'usually mean either feature envy on a missing collaborator or '
      'a missing parameter object. A common warning threshold is 4.';

  @override
  List<String> get refactorHints => const [
    'Group related parameters into a record or a small data class.',
    'Promote the function to a method on the class that owns most of the inputs (Fowler\'s "Move Method").',
    'Replace boolean / enum flags with separate, intent-named methods.',
    'Use named parameters with sensible defaults to remove the long positional tail.',
  ];

  @override
  num compute(FunctionMetricInput input) {
    return input.parameters?.parameters.length ?? 0;
  }
}
