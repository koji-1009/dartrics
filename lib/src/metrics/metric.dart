import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

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
    required this.body,
    required this.parameters,
    required this.scopeName,
  });

  /// Constructs the input from a [FunctionDeclaration],
  /// [MethodDeclaration], or [ConstructorDeclaration]. Other declaration
  /// kinds are rejected at the type system level by the engine, which
  /// only ever calls this factory.
  factory FunctionMetricInput.fromDeclaration({
    required CompilationUnit unit,
    required String source,
    required LineInfo lineInfo,
    required Declaration declaration,
  }) {
    final body = _bodyOf(declaration);
    final parameters = _parametersOf(declaration);
    final scopeName = _scopeNameOf(declaration);
    return FunctionMetricInput(
      unit: unit,
      source: source,
      lineInfo: lineInfo,
      declaration: declaration,
      body: body,
      parameters: parameters,
      scopeName: scopeName,
    );
  }

  final CompilationUnit unit;
  final String source;
  final LineInfo lineInfo;

  /// One of [FunctionDeclaration], [MethodDeclaration], or
  /// [ConstructorDeclaration].
  final Declaration declaration;

  final FunctionBody body;
  final FormalParameterList? parameters;

  /// Human-readable scope name. For top-level functions, the function name.
  /// For methods/constructors, `Class.name` (named-constructor name preserved).
  final String scopeName;
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
