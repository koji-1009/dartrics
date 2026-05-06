import 'dart:math' as math;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

import '../metric.dart';

/// Counts of Halstead operators and operands within a single function body.
///
/// Tokens are classified as:
/// - **Operands**: identifiers, all literals (number, string, boolean, null).
/// - **Operators**: every other token — keywords (`if`, `return`, ...) and
///   symbolic operators / punctuation (`+`, `=`, `(`, `;`, ...).
///
/// String interpolation expressions ($expr / ${expr}) are visited through
/// their child tokens just like any other syntax.
class HalsteadCounts {
  HalsteadCounts({
    required this.uniqueOperators,
    required this.uniqueOperands,
    required this.totalOperators,
    required this.totalOperands,
  });

  /// `n1` — distinct operators.
  final int uniqueOperators;

  /// `n2` — distinct operands.
  final int uniqueOperands;

  /// `N1` — total operators.
  final int totalOperators;

  /// `N2` — total operands.
  final int totalOperands;

  int get vocabulary => uniqueOperators + uniqueOperands;
  int get length => totalOperators + totalOperands;

  /// Halstead Volume `V = N · log2(η)`.
  double get volume {
    if (vocabulary <= 1) return 0;
    return length * (math.log(vocabulary) / math.ln2);
  }

  /// Halstead Difficulty `D = (n1 / 2) · (N2 / n2)`.
  double get difficulty {
    if (uniqueOperands == 0) return 0;
    return (uniqueOperators / 2) * (totalOperands / uniqueOperands);
  }

  /// Halstead Effort `E = D · V`.
  double get effort => difficulty * volume;

  static HalsteadCounts fromBody(FunctionBody body) {
    final operators = <String, int>{};
    final operands = <String, int>{};
    Token? token = body.beginToken;
    final end = body.endToken;
    while (token != null) {
      final bucket = _isOperand(token) ? operands : operators;
      bucket.update(token.lexeme, (v) => v + 1, ifAbsent: () => 1);
      if (token == end) break;
      token = token.next;
    }
    return HalsteadCounts(
      uniqueOperators: operators.length,
      uniqueOperands: operands.length,
      totalOperators: operators.values.fold(0, (a, b) => a + b),
      totalOperands: operands.values.fold(0, (a, b) => a + b),
    );
  }
}

const _operandTokenTypes = <TokenType>{
  TokenType.IDENTIFIER,
  TokenType.STRING,
  TokenType.INT,
  TokenType.DOUBLE,
  TokenType.HEXADECIMAL,
};
const _operandLiteralLexemes = <String>{'true', 'false', 'null'};

bool _isOperand(Token token) =>
    _operandTokenTypes.contains(token.type) ||
    _operandLiteralLexemes.contains(token.lexeme);

/// Halstead Volume — `N · log2(η)`. (Halstead, 1977.)
///
/// Off by default: a half-century of empirical research has not shown a
/// predictive advantage over cyclomatic complexity. Opt in via
/// `dartrics: { metrics: { halstead-volume: { enabled: true } } }`.
class HalsteadVolume extends FunctionMetric {
  const HalsteadVolume();
  @override
  String get id => 'halstead-volume';
  @override
  bool get defaultEnabled => false;
  @override
  String get rationale =>
      'Halstead Volume `V = N · log₂(η)` (Halstead, *Elements of '
      'Software Science*, 1977) describes the "amount of mental work" '
      'needed to read a function: it grows with both program length '
      '`N` (total operators + operands) and vocabulary `η` (distinct '
      'operators + operands). Off by default — a half century of '
      'empirical follow-up has not shown a predictive advantage over '
      'cyclomatic complexity, but it is sometimes useful inside the '
      'maintainability index.';

  @override
  List<String> get refactorHints => const [
    'Extract repeated sub-expressions into named local variables.',
    'Reduce vocabulary by reusing helper functions instead of duplicating literal constants and operators.',
    'Split the function — Halstead Volume is roughly additive across helpers so each piece becomes easier to read.',
  ];
  @override
  num compute(FunctionMetricInput input) =>
      HalsteadCounts.fromBody(input.body).volume;
}

/// Halstead Difficulty — `(n1/2) · (N2/n2)`. (Halstead, 1977.) Off by
/// default; see [HalsteadVolume].
class HalsteadDifficulty extends FunctionMetric {
  const HalsteadDifficulty();
  @override
  String get id => 'halstead-difficulty';
  @override
  bool get defaultEnabled => false;
  @override
  String get rationale =>
      'Halstead Difficulty `D = (n₁ / 2) · (N₂ / n₂)` (Halstead, 1977) '
      'attempts to quantify how error-prone a function is to write, by '
      'weighting the number of distinct operators against the average '
      'reuse of each operand. Off by default for the same reason as '
      '`halstead-volume`.';

  @override
  List<String> get refactorHints => const [
    'Reuse the same variable name for the same logical value rather than introducing fresh names per branch.',
    'Replace recurring symbolic operators (e.g. repeated bit-shifts) with a helper that names what they compute.',
  ];
  @override
  num compute(FunctionMetricInput input) =>
      HalsteadCounts.fromBody(input.body).difficulty;
}

/// Halstead Effort — `D · V`. (Halstead, 1977.) Off by default; see
/// [HalsteadVolume].
class HalsteadEffort extends FunctionMetric {
  const HalsteadEffort();
  @override
  String get id => 'halstead-effort';
  @override
  bool get defaultEnabled => false;
  @override
  String get rationale =>
      'Halstead Effort `E = D · V` (Halstead, 1977) is the product of '
      'difficulty and volume; the original conjecture is that it scales '
      'with the number of mental "elementary discriminations" a reader '
      'must make. Off by default for the same reason as the other '
      'Halstead metrics.';

  @override
  List<String> get refactorHints => const [
    'Apply both the volume and difficulty hints — effort drops multiplicatively when either factor goes down.',
    'Consider whether the function should be split into pieces with individually low effort scores.',
  ];
  @override
  num compute(FunctionMetricInput input) =>
      HalsteadCounts.fromBody(input.body).effort;
}
