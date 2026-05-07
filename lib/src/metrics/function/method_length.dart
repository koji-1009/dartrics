import '../metric.dart';

/// Method Length (LOC) — total number of source lines spanned by the
/// function body, *including* blank lines and comments.
///
/// Off by default in 0.1.0: in production code its correlation with
/// `source-lines-of-code` is high enough (often > 0.95) that emitting
/// both lenses produces redundant violations on the same scope. Opt in
/// when you specifically want the "how big is this thing on screen"
/// reading (which counts blanks + comment lines) on top of SLOC's
/// "actual code volume" reading.
class MethodLength extends FunctionMetric {
  const MethodLength();

  @override
  String get id => 'method-length';

  @override
  bool get defaultEnabled => false;

  @override
  String get rationale =>
      'Method length is the total number of source lines spanned by '
      'the function body, including blanks and comments. Unlike '
      '`source-lines-of-code`, it answers "how big is this thing on '
      'screen" — a coarse readability signal that pairs with SLOC. '
      'Beck (*Smalltalk Best Practice Patterns*, 1996) advocates for '
      'methods short enough to fit on a screen, often interpreted as '
      '50–80 lines. Off by default in 0.1.0 because the correlation '
      'with SLOC in production code is high enough that emitting both '
      'lenses on the same scope is redundant noise for AI loops; opt '
      'in when you specifically want the screen-real-estate reading.';

  @override
  List<String> get refactorHints => const [
    'Extract sub-steps into named helpers — each helper documents the step\'s intent for free.',
    'Collapse stretches of doc/banner comments into a single dartdoc block above the method.',
    'Split functions that handle multiple concerns (validation, computation, formatting) into one function per concern.',
  ];

  @override
  num compute(FunctionMetricInput input) {
    final start = input.lineInfo.getLocation(input.body.offset).lineNumber;
    final end = input.lineInfo.getLocation(input.body.end).lineNumber;
    return end - start + 1;
  }
}
