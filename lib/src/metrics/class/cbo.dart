import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'class_metric.dart';

/// Coupling Between Objects (CBO, Chidamber & Kemerer 1994) — count of
/// distinct **other** types that the class references via member signatures
/// (field/parameter/return types) and method bodies.
///
/// Uses syntactic name matching only: every `NamedType` name appearing
/// anywhere inside the class declaration is collected, then the class's own
/// name is removed. This intentionally counts external types too — it
/// answers "how many types does this class touch" rather than "how many
/// other internal types does this class touch".
class CouplingBetweenObjects extends ClassMetric {
  const CouplingBetweenObjects();

  @override
  String get id => 'coupling-between-objects';

  @override
  num compute(ClassMetricInput input) {
    final visitor = _NamedTypeCollector();
    input.declaration.accept(visitor);
    final names = visitor.names
      ..remove(input.className)
      ..removeAll(_alwaysIgnore);
    return names.length;
  }
}

const _alwaysIgnore = {
  // Common parametric/utility names that aren't user-domain coupling.
  'void',
  'dynamic',
  'Never',
};

class _NamedTypeCollector extends RecursiveAstVisitor<void> {
  final names = <String>{};

  @override
  void visitNamedType(NamedType node) {
    names.add(node.name.lexeme);
    super.visitNamedType(node);
  }
}
