import 'package:analyzer/dart/ast/ast.dart';

import 'class_metric.dart';

/// Number of Methods (NOM) — count of method-like members declared on the
/// class body, including getters, setters, operators, and constructors with
/// non-empty bodies. Field declarations and abstract members with empty
/// bodies are excluded.
class NumberOfMethods extends ClassMetric {
  const NumberOfMethods();

  @override
  String get id => 'number-of-methods';

  @override
  String get rationale =>
      'Number of methods (NOM) counts method-shaped members declared on '
      'the class — methods, getters, setters, operators, and '
      'constructors with non-empty bodies. Abstract members and field '
      'declarations are excluded. NOM is one of the simplest size '
      'metrics for a class; large values often correlate with classes '
      'that violate the single-responsibility principle. A typical '
      'warning threshold is 20.';

  @override
  List<String> get refactorHints => const [
    'Extract a coherent subset of methods into a collaborator class ("Extract Class", Fowler 1999).',
    'Move feature-specific methods onto the type that actually owns the data they touch.',
    'Replace many small accessors with a single immutable record or data class.',
  ];

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
