import 'class_metric.dart';

/// Number of Children (NOC, Chidamber & Kemerer 1994) — count of *direct*
/// subclasses found in the analysis root.
class NumberOfChildren implements ClassMetric {
  const NumberOfChildren();

  @override
  String get id => 'number-of-children';

  @override
  num compute(ClassMetricInput input) {
    return input.index.directChildren[input.className]?.length ?? 0;
  }
}
