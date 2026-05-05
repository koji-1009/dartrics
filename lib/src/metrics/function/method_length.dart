import '../metric.dart';

/// Method Length (LOC) — total number of source lines spanned by the
/// function body, *including* blank lines and comments. Useful as a coarse
/// "how big is this method" indicator, complementing the more precise
/// [SourceLinesOfCode] metric.
class MethodLength implements FunctionMetric {
  const MethodLength();

  @override
  String get id => 'method-length';

  @override
  num compute(FunctionMetricInput input) {
    final body = input.body;
    if (body == null) return 0;
    final start = input.lineInfo.getLocation(body.offset).lineNumber;
    final end = input.lineInfo.getLocation(body.end).lineNumber;
    return end - start + 1;
  }
}
