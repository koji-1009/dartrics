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
  ClassIndex._({required this.byName});

  final Map<String, ClassDeclaration> byName;

  static ClassIndex build(Iterable<ClassDeclaration> classes) {
    final byName = <String, ClassDeclaration>{};
    for (final cls in classes) {
      byName[cls.namePart.typeName.lexeme] = cls;
    }
    return ClassIndex._(byName: byName);
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
  const ClassMetric();

  String get id;
  bool get defaultEnabled => true;
  num compute(ClassMetricInput input);
}
