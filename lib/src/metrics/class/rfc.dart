import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'class_metric.dart';

/// Response For a Class (RFC, Chidamber & Kemerer 1994) —
/// `RFC = |M ∪ R|`, where:
/// - `M` is the set of methods declared by the class, and
/// - `R` is the set of *distinct* method names invoked from those methods.
///
/// Detection is name-based on the AST (every `MethodInvocation` and
/// constructor call), so cross-shadow false-positives are possible but rare
/// for the order-of-magnitude purpose this metric serves.
class ResponseForClass implements ClassMetric {
  const ResponseForClass();

  @override
  String get id => 'response-for-class';

  @override
  num compute(ClassMetricInput input) {
    final cls = input.declaration;
    final declared = <String>{};
    final invoked = <String>{};

    for (final member in cls.body.members) {
      if (member is MethodDeclaration && member.body is! EmptyFunctionBody) {
        declared.add(member.name.lexeme);
        member.body.accept(_InvocationCollector(invoked));
      } else if (member is ConstructorDeclaration &&
          member.body is! EmptyFunctionBody) {
        declared.add(member.name?.lexeme ?? input.className);
        member.body.accept(_InvocationCollector(invoked));
      }
    }
    final union = <String>{}
      ..addAll(declared)
      ..addAll(invoked);
    return union.length;
  }
}

class _InvocationCollector extends RecursiveAstVisitor<void> {
  _InvocationCollector(this.target);
  final Set<String> target;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    target.add(node.methodName.name);
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final name = node.constructorName.type.name.lexeme;
    target.add(name);
    super.visitInstanceCreationExpression(node);
  }
}
