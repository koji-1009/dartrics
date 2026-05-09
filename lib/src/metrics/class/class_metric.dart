import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../metric.dart';

class ClassMetricInput {
  ClassMetricInput({required this.declaration, required this.lineInfo});

  final ClassDeclaration declaration;
  final LineInfo lineInfo;

  String get className => declaration.namePart.typeName.lexeme;
}

abstract class ClassMetric {
  const ClassMetric();

  String get id;
  bool get defaultEnabled => true;

  /// One-paragraph explanation of what the metric measures, surfaced by
  /// `dartrics rules` and the `--explain` flag.
  String get rationale;

  /// Concrete refactor moves to take when the metric trips.
  List<String> get refactorHints;

  /// Original sources for the metric. See [FunctionMetric.references].
  List<String> get references => const [];

  /// Direction in which the value moves when the code gets healthier.
  /// See `FunctionMetric.polarity`.
  MetricPolarity get polarity => MetricPolarity.down;

  num compute(ClassMetricInput input);
}
