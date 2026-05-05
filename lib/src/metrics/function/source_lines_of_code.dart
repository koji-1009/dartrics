import '../metric.dart';

/// Source Lines of Code — non-blank, non-comment-only lines inside the
/// function body. Lines that are entirely a `//` comment, entirely inside a
/// `/* … */` block, or whitespace are excluded; lines with code followed by
/// a trailing comment count once.
class SourceLinesOfCode implements FunctionMetric {
  const SourceLinesOfCode();

  @override
  String get id => 'source-lines-of-code';

  @override
  num compute(FunctionMetricInput input) {
    final body = input.body;
    if (body == null) return 0;
    final text = input.source.substring(body.offset, body.end);
    int count = 0;
    bool inBlockComment = false;

    for (final raw in text.split('\n')) {
      var line = raw;
      // First, peel off block comments that started on a previous line.
      if (inBlockComment) {
        final close = line.indexOf('*/');
        if (close < 0) continue;
        line = line.substring(close + 2);
        inBlockComment = false;
      }
      // Scan for any block comments that open on this line.
      while (true) {
        final open = line.indexOf('/*');
        if (open < 0) break;
        final close = line.indexOf('*/', open + 2);
        if (close < 0) {
          line = line.substring(0, open);
          inBlockComment = true;
          break;
        }
        line = line.substring(0, open) + line.substring(close + 2);
      }
      // Strip a trailing line comment.
      final lineComment = line.indexOf('//');
      if (lineComment >= 0) {
        line = line.substring(0, lineComment);
      }
      if (line.trim().isEmpty) continue;
      count++;
    }
    return count;
  }
}
