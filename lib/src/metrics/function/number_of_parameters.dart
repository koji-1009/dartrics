import '../metric.dart';

/// Number of **positional** formal parameters declared by the function.
///
/// Fowler's *Refactoring* (1999) flagged "long parameter list" as a code
/// smell on the basis that the call site `foo(a, b, c, d, e)` forces
/// the reader to count argument positions and recover each one's intent
/// by hand. Dart's named-parameter call site `foo(a: …, b: …, c: …)`
/// dissolves that load — every argument carries its name on the spot,
/// so the reader's working memory cost is constant in the number of
/// names. The metric therefore counts only positional parameters
/// (required + optional positional); named parameters — required or
/// optional — are intentionally weight-zero, mirroring how
/// [`boolean-trap`](boolean_trap.dart) treats the same axis.
///
/// This also pushes back on a real failure mode of AI-authored Dart:
/// agents trained on Java / TypeScript / Python tend to default to
/// positional signatures, which then trip the lens. The refactor hint
/// "promote to named" makes the right move the obvious one.
///
/// Constructor `this.foo` and super-parameter forms count when they sit
/// in the positional list, since the reader still recovers their role
/// by position at the call site.
class NumberOfParameters extends FunctionMetric {
  const NumberOfParameters();

  @override
  String get id => 'number-of-parameters';

  @override
  String get rationale =>
      'Counts the number of **positional** formal parameters (required + '
      'optional). Fowler (*Refactoring*, 1999) flagged long parameter '
      'lists as a code smell because the call site `foo(a, b, c, d, e)` '
      'forces the reader to recover each argument\'s intent by counting '
      'positions. Dart\'s named-parameter call site `foo(a: …, b: …)` '
      'dissolves that load: every argument carries its name on the '
      'spot, so a function with many named parameters reads cleanly '
      'regardless of count. Named parameters are therefore weight-zero, '
      'matching how `boolean-trap` treats the same axis. Default '
      'warning threshold is 4 — the smallest positional count where the '
      'call site loses self-documentation.';

  @override
  List<String> get refactorHints => const [
    'Promote positional parameters to named: `foo({required T a, required T b, …})`. The call site reads as `foo(a: …, b: …)` and the metric drops to zero.',
    'Group related positional parameters into a record or a small data class so the signature carries one structured argument instead of several scalars.',
    'Promote the function to a method on the class that owns most of the inputs (Fowler\'s "Move Method").',
    'Replace boolean / enum flags in the positional list with separate, intent-named methods or a typed enum.',
  ];

  @override
  List<String> get references => const [
    'Fowler, M. (1999). Refactoring: Improving the Design of Existing Code. Addison-Wesley.',
  ];

  @override
  num compute(FunctionMetricInput input) {
    final params = input.parameters;
    if (params == null) return 0;
    var count = 0;
    for (final p in params.parameters) {
      // Named parameters carry their name at the call site, which
      // dissolves the position-counting load Fowler's lens targets.
      // Only positional parameters (required + optional positional)
      // contribute to the count — same rule as `boolean-trap`.
      if (p.isNamed) continue;
      count++;
    }
    return count;
  }
}
