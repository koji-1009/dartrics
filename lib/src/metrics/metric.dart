import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

/// Bundle of unit-scoped inputs every function-level metric needs.
///
/// Kept as a record so `parseString` results, full `ResolvedUnitResult`
/// instances, and tests can all build one inline without an adapter type.
typedef UnitContext = ({
  CompilationUnit unit,
  String source,
  LineInfo lineInfo,
});

/// Bundle of inputs every function-level metric receives.
///
/// Decoupled from `ResolvedUnitResult` so that tests can run metrics over a
/// `parseString`-only result, which is significantly cheaper than full
/// resolution.
class FunctionMetricInput {
  FunctionMetricInput({required this.context, required this.declaration});

  final UnitContext context;

  /// One of [FunctionDeclaration], [MethodDeclaration], or
  /// [ConstructorDeclaration]; engines that build this input filter
  /// declaration kinds at collection time.
  final Declaration declaration;

  // `context.unit` is exposed via the record itself when needed; only the
  // two helpers below have call sites today.
  String get source => context.source;
  LineInfo get lineInfo => context.lineInfo;

  late final FunctionBody body = _bodyOf(declaration);
  late final FormalParameterList? parameters = _parametersOf(declaration);

  /// Human-readable scope name. For top-level functions, the function name.
  /// For methods/constructors, `Class.name` (named-constructor name preserved).
  late final String scopeName = _scopeNameOf(declaration);
}

/// Function/method-level metric.
abstract class FunctionMetric {
  /// Stable identifier (used as JSON key and threshold key).
  String get id;

  /// Computes the metric. Implementations must be deterministic.
  num compute(FunctionMetricInput input);
}

FunctionBody _bodyOf(Declaration d) {
  if (d is FunctionDeclaration) return d.functionExpression.body;
  if (d is MethodDeclaration) return d.body;
  return (d as ConstructorDeclaration).body;
}

FormalParameterList? _parametersOf(Declaration d) {
  if (d is FunctionDeclaration) return d.functionExpression.parameters;
  if (d is MethodDeclaration) return d.parameters;
  return (d as ConstructorDeclaration).parameters;
}

String _scopeNameOf(Declaration d) {
  if (d is FunctionDeclaration) return d.name.lexeme;
  if (d is MethodDeclaration) {
    final cls = _enclosingClassName(d);
    final method = d.name.lexeme;
    return cls == null ? method : '$cls.$method';
  }
  final ctor = (d as ConstructorDeclaration);
  final cls = _enclosingClassName(ctor) ?? '<anonymous>';
  final name = ctor.name?.lexeme;
  return name == null ? cls : '$cls.$name';
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
