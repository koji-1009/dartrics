import 'class_metric.dart';

/// Class Length (LOC) — total source lines spanned by the class declaration,
/// including its body braces, member definitions, blank lines, and comments.
class ClassLength implements ClassMetric {
  const ClassLength();

  @override
  String get id => 'class-length';

  @override
  num compute(ClassMetricInput input) {
    final start = input.lineInfo
        .getLocation(input.declaration.offset)
        .lineNumber;
    final end = input.lineInfo.getLocation(input.declaration.end).lineNumber;
    return end - start + 1;
  }
}
