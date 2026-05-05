import 'package:analyzer/dart/ast/ast.dart';

import '../function/cyclomatic_complexity.dart';
import '../metric.dart';
import 'class_metric.dart';

/// Weighted Methods per Class (WMC, Chidamber & Kemerer 1994) — sum of the
/// cyclomatic complexity of every method-like member of the class.
class WeightedMethodsPerClass implements ClassMetric {
  const WeightedMethodsPerClass();

  @override
  String get id => 'weighted-methods-per-class';

  @override
  num compute(ClassMetricInput input) {
    const cc = CyclomaticComplexity();
    final cls = input.declaration;
    final unit = cls.thisOrAncestorOfType<CompilationUnit>();
    if (unit == null) return 0;
    var total = 0;
    for (final member in cls.body.members) {
      if (member is MethodDeclaration && member.body is! EmptyFunctionBody) {
        total += cc.compute(_inputFor(unit, member)).toInt();
      } else if (member is ConstructorDeclaration &&
          member.body is! EmptyFunctionBody) {
        total += cc.compute(_inputFor(unit, member)).toInt();
      }
    }
    return total;
  }

  FunctionMetricInput _inputFor(CompilationUnit unit, Declaration decl) {
    return FunctionMetricInput(
      unit: unit,
      // Halstead/SLOC are not needed for CC; pass an empty source so any
      // accidental token-level usage will fail loudly rather than silently
      // produce wrong values.
      source: '',
      lineInfo: unit.lineInfo,
      declaration: decl,
    );
  }
}
