import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

/// What scope of program element a metric describes.
enum MetricLevel { function, klass, library }

/// Bundle of inputs every function-level metric receives.
///
/// Decoupled from `ResolvedUnitResult` so that tests can run metrics over a
/// `parseString`-only result, which is significantly cheaper than full
/// resolution.
class FunctionMetricInput {
  FunctionMetricInput({
    required this.unit,
    required this.source,
    required this.lineInfo,
    required this.declaration,
  });

  final CompilationUnit unit;
  final String source;
  final LineInfo lineInfo;

  /// One of [FunctionDeclaration], [MethodDeclaration], or
  /// [ConstructorDeclaration].
  final Declaration declaration;

  FunctionBody? get body {
    final d = declaration;
    if (d is FunctionDeclaration) return d.functionExpression.body;
    if (d is MethodDeclaration) return d.body;
    if (d is ConstructorDeclaration) return d.body;
    return null;
  }

  FormalParameterList? get parameters {
    final d = declaration;
    if (d is FunctionDeclaration) return d.functionExpression.parameters;
    if (d is MethodDeclaration) return d.parameters;
    if (d is ConstructorDeclaration) return d.parameters;
    return null;
  }

  /// Human-readable scope name. For top-level functions, the function name.
  /// For methods/constructors, `Class.name` (named-constructor name preserved).
  String get scopeName {
    final d = declaration;
    if (d is FunctionDeclaration) return d.name.lexeme;
    if (d is MethodDeclaration) {
      final cls = _enclosingClassName(d);
      final method = d.name.lexeme;
      return cls == null ? method : '$cls.$method';
    }
    if (d is ConstructorDeclaration) {
      final cls = _enclosingClassName(d);
      final ctor = d.name?.lexeme;
      final base = cls ?? '<anonymous>';
      return ctor == null ? base : '$base.$ctor';
    }
    return '<unknown>';
  }

  String? _enclosingClassName(AstNode node) {
    AstNode? parent = node.parent;
    while (parent != null) {
      if (parent is ClassDeclaration) return parent.namePart.typeName.lexeme;
      if (parent is MixinDeclaration) return parent.name.lexeme;
      if (parent is ExtensionDeclaration) {
        return parent.name?.lexeme ?? '<extension>';
      }
      if (parent is EnumDeclaration) return parent.namePart.typeName.lexeme;
      parent = parent.parent;
    }
    return null;
  }

  int get bodyStartLine => lineInfo.getLocation(declaration.offset).lineNumber;
}

/// Function/method-level metric.
abstract class FunctionMetric {
  /// Stable identifier (used as JSON key and threshold key).
  String get id;

  /// Computes the metric. Implementations must be deterministic.
  num compute(FunctionMetricInput input);
}
