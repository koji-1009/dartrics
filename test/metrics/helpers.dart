import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:dartrics/src/metrics/metric.dart';

/// Parses [source] and returns a [FunctionMetricInput] for the function or
/// method matching [name]. Falls back to the first declaration when [name]
/// is omitted. [isTestFile] feeds the input's test-file flag so tests can
/// exercise path-sensitive lenses without a real file path.
FunctionMetricInput inputFor(
  String source, {
  String? name,
  bool isTestFile = false,
}) {
  final result = parseString(content: source);
  final visitor = _Finder(name);
  result.unit.accept(visitor);
  final found = visitor.match;
  if (found == null) {
    throw StateError('No function named "$name" found in source.');
  }
  return FunctionMetricInput(
    context: (unit: result.unit, source: source, lineInfo: result.lineInfo),
    declaration: found,
    isTestFile: isTestFile,
  );
}

/// Parses [source] and returns a [FunctionMetricInput] for the [index]-th
/// (0-based, pre-order) closure — function literals that are not the body
/// of a named declaration, mirroring the engine's collection rule.
FunctionMetricInput closureInputFor(
  String source, {
  int index = 0,
  bool isTestFile = false,
}) {
  final result = parseString(content: source);
  final visitor = _ClosureFinder();
  result.unit.accept(visitor);
  return FunctionMetricInput(
    context: (unit: result.unit, source: source, lineInfo: result.lineInfo),
    declaration: visitor.closures[index],
    isTestFile: isTestFile,
  );
}

class _ClosureFinder extends RecursiveAstVisitor<void> {
  final closures = <FunctionExpression>[];

  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (node.parent is! FunctionDeclaration) closures.add(node);
    super.visitFunctionExpression(node);
  }
}

class _Finder extends RecursiveAstVisitor<void> {
  _Finder(this.name);
  final String? name;
  Declaration? match;

  bool _accept(String? candidate) =>
      name == null ? match == null : candidate == name;

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (match != null) return;
    if (_accept(node.name.lexeme)) match = node;
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (match != null) return;
    if (_accept(node.name.lexeme)) match = node;
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    if (match != null) return;
    if (_accept(node.name?.lexeme)) match = node;
    super.visitConstructorDeclaration(node);
  }
}
