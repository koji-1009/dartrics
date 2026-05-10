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

  late final CallableDecl _callable = CallableDecl.from(declaration);
  late final FunctionBody body = _callable.body;
  late final FormalParameterList? parameters = _callable.parameters;

  /// Human-readable scope name. For top-level functions, the function name.
  /// For methods/constructors, `Class.name` (named-constructor name preserved).
  late final String scopeName = _callable.scopeName;
}

/// Direction in which a metric value moves when the underlying code
/// gets healthier. Used by `dartrics regression` to classify before /
/// after diffs as `improved` / `regressed` / `unchanged`.
enum MetricPolarity {
  /// Lower values are healthier (e.g. cyclomatic complexity, SLOC).
  down,

  /// Either direction can be a sign of improvement depending on the
  /// design role (e.g. instability, coupling totals). Regression diffs
  /// surface the delta but don't classify it.
  neutral,
}

/// Function/method-level metric.
abstract class FunctionMetric {
  const FunctionMetric();

  /// Stable identifier (used as JSON key and threshold key).
  String get id;

  /// Whether this metric runs by default. Override to `false` for
  /// experimental / historical metrics that users opt into via
  /// `analysis_options.yaml`'s `dartrics: { metrics: { <id>: { enabled: true } } }`.
  bool get defaultEnabled => true;

  /// One-paragraph explanation of what the metric measures, the source it
  /// is taken from, and the reasoning behind the default threshold. Surfaced
  /// by `dartrics rules` and the auto-explain block of the AI / md / SARIF
  /// reporters so AI loops can learn the metric's intent without re-deriving
  /// it from training data.
  String get rationale;

  /// Concrete refactor moves a developer (or AI agent) can take when the
  /// metric trips. Each entry is a single short imperative sentence.
  List<String> get refactorHints;

  /// Original sources for the metric — papers, books, or specs the
  /// definition is anchored to. Each entry is a short citation
  /// ("Author (Year). Title. Venue."). Return `const []` for metrics
  /// that don't trace to a published source. Surfaced by `dartrics
  /// rules` and the AI report so an agent reading dartrics output can
  /// verify a metric against its primary source.
  List<String> get references;

  /// Direction in which the value moves when the code gets healthier.
  /// Override to `neutral` for metrics where neither direction is
  /// universally good (e.g. Halstead Volume).
  MetricPolarity get polarity => .down;

  /// Computes the metric. Implementations must be deterministic.
  num compute(FunctionMetricInput input);
}

/// Sealed wrapper over the three [Declaration] subtypes that the
/// function-level metric layer cares about. The factory in [from] is
/// the single place that talks to analyzer's open `Declaration`
/// hierarchy, so per-kind dispatch elsewhere reduces to virtual
/// method calls and the surrounding code stays exhaustiveness-checked
/// without a wildcard arm.
sealed class CallableDecl {
  const CallableDecl();

  /// Wraps [d]. Engines that build [FunctionMetricInput] filter
  /// declaration kinds at collection time, so the trailing cast is a
  /// type assertion, not a dispatch fallback.
  factory CallableDecl.from(Declaration d) {
    if (d is FunctionDeclaration) return _FunctionCallable(d);
    if (d is MethodDeclaration) return _MethodCallable(d);
    return _CtorCallable(d as ConstructorDeclaration);
  }

  FunctionBody get body;
  FormalParameterList? get parameters;
  String get scopeName;
}

class _FunctionCallable extends CallableDecl {
  const _FunctionCallable(this.node);
  final FunctionDeclaration node;
  @override
  FunctionBody get body => node.functionExpression.body;
  @override
  FormalParameterList? get parameters => node.functionExpression.parameters;
  @override
  String get scopeName => node.name.lexeme;
}

class _MethodCallable extends CallableDecl {
  const _MethodCallable(this.node);
  final MethodDeclaration node;
  @override
  FunctionBody get body => node.body;
  @override
  FormalParameterList? get parameters => node.parameters;
  @override
  String get scopeName {
    final cls = _enclosingClassName(node);
    return cls == null ? node.name.lexeme : '$cls.${node.name.lexeme}';
  }
}

class _CtorCallable extends CallableDecl {
  const _CtorCallable(this.node);
  final ConstructorDeclaration node;
  @override
  FunctionBody get body => node.body;
  @override
  FormalParameterList? get parameters => node.parameters;
  @override
  String get scopeName {
    final cls = _enclosingClassName(node) ?? '<anonymous>';
    final name = node.name?.lexeme;
    return name == null ? cls : '$cls.$name';
  }
}

String? _enclosingClassName(AstNode node) {
  for (var parent = node.parent; parent != null; parent = parent.parent) {
    final name = switch (parent) {
      ClassDeclaration(:final namePart) => namePart.typeName.lexeme,
      MixinDeclaration(:final name) => name.lexeme,
      ExtensionDeclaration(:final name) => name?.lexeme ?? '<extension>',
      EnumDeclaration(:final namePart) => namePart.typeName.lexeme,
      _ => null,
    };
    if (name != null) return name;
  }
  return null;
}
