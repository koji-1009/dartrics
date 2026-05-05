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
      final type = token.type;
      final isOperand =
          type == TokenType.IDENTIFIER ||
          type == TokenType.STRING ||
          type == TokenType.INT ||
          type == TokenType.DOUBLE ||
          type == TokenType.HEXADECIMAL ||
          token.lexeme == 'true' ||
          token.lexeme == 'false' ||
          token.lexeme == 'null';
      if (isOperand) {
        operands.update(token.lexeme, (v) => v + 1, ifAbsent: () => 1);
      } else {
        operators.update(token.lexeme, (v) => v + 1, ifAbsent: () => 1);
      }
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

/// Halstead Volume — `N · log2(η)`. (Halstead, 1977.)
class HalsteadVolume implements FunctionMetric {
  const HalsteadVolume();
  @override
  String get id => 'halstead-volume';
  @override
  num compute(FunctionMetricInput input) =>
      HalsteadCounts.fromBody(input.body).volume;
}

/// Halstead Difficulty — `(n1/2) · (N2/n2)`. (Halstead, 1977.)
class HalsteadDifficulty implements FunctionMetric {
  const HalsteadDifficulty();
  @override
  String get id => 'halstead-difficulty';
  @override
  num compute(FunctionMetricInput input) =>
      HalsteadCounts.fromBody(input.body).difficulty;
}

/// Halstead Effort — `D · V`. (Halstead, 1977.)
class HalsteadEffort implements FunctionMetric {
  const HalsteadEffort();
  @override
  String get id => 'halstead-effort';
  @override
  num compute(FunctionMetricInput input) =>
      HalsteadCounts.fromBody(input.body).effort;
}
