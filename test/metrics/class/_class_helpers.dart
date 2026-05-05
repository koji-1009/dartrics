import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:dartrics/src/metrics/class/class_metric.dart';

/// Parses [source] and produces a [ClassMetricInput] for the named class,
/// indexed against every class found in the same source.
ClassMetricInput inputFor(String source, {required String className}) {
  final result = parseString(content: source);
  final visitor = _ClassFinder();
  result.unit.accept(visitor);
  final target = visitor.classes
      .firstWhere((c) => c.namePart.typeName.lexeme == className,
          orElse: () => throw StateError('class $className not found'));
  final index = ClassIndex.build(visitor.classes);
  return ClassMetricInput(
    declaration: target,
    lineInfo: result.lineInfo,
    index: index,
  );
}

class _ClassFinder extends RecursiveAstVisitor<void> {
  final classes = <ClassDeclaration>[];

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    classes.add(node);
    super.visitClassDeclaration(node);
  }
}
