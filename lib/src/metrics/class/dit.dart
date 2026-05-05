import 'package:analyzer/dart/ast/ast.dart';

import 'class_metric.dart';

/// Depth of Inheritance Tree (DIT, Chidamber & Kemerer 1994) — length of the
/// longest path from this class to the root (`Object`), counted in
/// inheritance steps.
///
/// Convention used here: a class with no explicit `extends` clause has
/// `DIT = 1` (one step from `Object`); a direct subclass adds 1 each level.
/// External superclasses (declared outside the analysis root) collapse to a
/// single additional step.
class DepthOfInheritanceTree implements ClassMetric {
  const DepthOfInheritanceTree();

  @override
  String get id => 'depth-of-inheritance-tree';

  @override
  num compute(ClassMetricInput input) {
    final visited = <String>{};
    return _depth(input.declaration, input.index, visited);
  }

  int _depth(ClassDeclaration cls, ClassIndex index, Set<String> visited) {
    final name = cls.namePart.typeName.lexeme;
    if (!visited.add(name)) {
      // Cycle (shouldn't happen in valid Dart) — bail out at the cycle root.
      return 1;
    }
    final ext = cls.extendsClause;
    if (ext == null) return 1;
    final parentName = ext.superclass.name.lexeme;
    if (parentName == 'Object') return 1;
    final parent = index.byName[parentName];
    if (parent == null) return 2; // External parent: parent → Object.
    return 1 + _depth(parent, index, visited);
  }
}
