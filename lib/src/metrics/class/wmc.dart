import 'package:analyzer/dart/ast/ast.dart';

import '../function/cyclomatic_complexity.dart';
import '../metric.dart';
import 'class_metric.dart';

/// Weighted Methods per Class (WMC, Chidamber & Kemerer 1994) — sum of the
/// cyclomatic complexity of every method-like member of the class.
class WeightedMethodsPerClass extends ClassMetric {
  const WeightedMethodsPerClass();

  @override
  String get id => 'weighted-methods-per-class';

  @override
  String get rationale =>
      'Weighted Methods per Class (WMC, Chidamber & Kemerer 1994) is '
      'the sum of the cyclomatic complexity of every method-shaped '
      'member of the class. It captures both the size and the '
      'branchiness of the class in one number; high values predict '
      'higher maintenance and testing cost. CK proposed it as one of '
      'six object-oriented design metrics; SonarQube uses ~30–50 as a '
      'typical alarm range.';

  @override
  List<String> get refactorHints => const [
    'Apply the cyclomatic-complexity refactor hints to the heaviest individual methods first.',
    'Move high-CC methods that don\'t depend on this class\'s state onto the type that does.',
    'Extract a strategy / state object so each branch lives on a small dedicated class.',
  ];

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
      // Halstead/SLOC need `source`, but CC doesn't; passing an empty
      // string makes any accidental token-level use fail loudly rather
      // than silently produce wrong values.
      context: (unit: unit, source: '', lineInfo: unit.lineInfo),
      declaration: decl,
    );
  }
}
