import 'package:analyzer/dart/ast/ast.dart';

import 'class_metric.dart';

/// Number of Methods (NOM) — count of method-like members declared on the
/// class body, including getters, setters, operators, and constructors with
/// non-empty bodies. Field declarations and abstract members with empty
/// bodies are excluded.
class NumberOfMethods implements ClassMetric {
  const NumberOfMethods();

  @override
  String get id => 'number-of-methods';

  @override
  num compute(ClassMetricInput input) {
    var count = 0;
    for (final member in input.declaration.body.members) {
      if (member is MethodDeclaration && member.body is! EmptyFunctionBody) {
        count++;
      } else if (member is ConstructorDeclaration &&
          member.body is! EmptyFunctionBody) {
        count++;
      }
    }
    return count;
  }
}
