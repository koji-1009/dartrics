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
    final text = input.source.substring(input.body.offset, input.body.end);
    final cursor = _CommentCursor();
    var count = 0;
    for (final raw in text.split('\n')) {
      if (cursor.stripCommentsAndCheckHasCode(raw)) count++;
    }
    return count;
  }
}

/// Walks a function body line by line stripping comments. Owns a small
/// "currently inside `/* … */`" flag so multi-line block comments survive
/// across iterations without leaking into the metric loop.
class _CommentCursor {
  bool _inBlockComment = false;

  /// Returns `true` when the line, after stripping comments, contains any
  /// non-whitespace code.
  bool stripCommentsAndCheckHasCode(String raw) {
    final afterBlock = _peelOpenBlockComment(raw);
    if (afterBlock == null) return false;
    final afterAllBlocks = _stripInlineBlockComments(afterBlock);
    final afterLineComment = _stripLineComment(afterAllBlocks);
    return afterLineComment.trim().isNotEmpty;
  }

  /// Strips the trailing portion of any block comment that started on a
  /// previous line. Returns `null` if the entire line is still inside the
  /// open comment.
  String? _peelOpenBlockComment(String line) {
    if (!_inBlockComment) return line;
    final close = line.indexOf('*/');
    if (close < 0) return null;
    _inBlockComment = false;
    return line.substring(close + 2);
  }

  /// Removes any complete `/* … */` blocks from [line]. If the line opens
  /// a block comment that doesn't close on the same line, marks the cursor
  /// as inside a block and trims everything from the opener.
  String _stripInlineBlockComments(String line) {
    var current = line;
    while (true) {
      final open = current.indexOf('/*');
      if (open < 0) return current;
      final close = current.indexOf('*/', open + 2);
      if (close < 0) {
        _inBlockComment = true;
        return current.substring(0, open);
      }
      current = current.substring(0, open) + current.substring(close + 2);
    }
  }

  String _stripLineComment(String line) {
    final lineComment = line.indexOf('//');
    return lineComment < 0 ? line : line.substring(0, lineComment);
  }
}
