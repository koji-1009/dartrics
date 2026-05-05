import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

/// Cross-class index built once per `MetricEngine.analyze` invocation.
///
/// Look-ups are by unqualified class name; this is intentionally lossy across
/// libraries that share class names. The trade-off is acceptable for v1: the
/// alternative requires resolving every supertype reference through the
/// element model, which is significantly slower and not needed for the
/// typical mid-size project.
class ClassIndex {
  ClassIndex._({required this.byName, required this.directChildren});

  final Map<String, ClassDeclaration> byName;
  final Map<String, List<String>> directChildren;

  static ClassIndex build(Iterable<ClassDeclaration> classes) {
    final byName = <String, ClassDeclaration>{};
    for (final cls in classes) {
      byName[cls.namePart.typeName.lexeme] = cls;
    }
    final children = <String, List<String>>{};
    for (final entry in byName.entries) {
      final ext = entry.value.extendsClause?.superclass.name.lexeme;
      if (ext != null) {
        children.putIfAbsent(ext, () => []).add(entry.key);
      }
    }
    return ClassIndex._(byName: byName, directChildren: children);
  }
}

class ClassMetricInput {
  ClassMetricInput({
    required this.declaration,
    required this.lineInfo,
    required this.index,
  });

  final ClassDeclaration declaration;
  final LineInfo lineInfo;
  final ClassIndex index;

  String get className => declaration.namePart.typeName.lexeme;
}

abstract class ClassMetric {
  String get id;
  num compute(ClassMetricInput input);
}
