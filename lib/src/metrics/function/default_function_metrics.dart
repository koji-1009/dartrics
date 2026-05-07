import '../metric.dart';
import 'boolean_trap.dart';
import 'cognitive_complexity.dart';
import 'cyclomatic_complexity.dart';
import 'halstead.dart';
import 'max_nesting_level.dart';
import 'method_length.dart';
import 'number_of_parameters.dart';
import 'source_lines_of_code.dart';
import 'widget_tree_depth.dart';

/// Set of function-level metrics enabled by default.
///
/// Order matters only for stable JSON output (the engine preserves it in the
/// emitted `values` map).
const List<FunctionMetric> defaultFunctionMetrics = [
  CyclomaticComplexity(),
  CognitiveComplexity(),
  HalsteadVolume(),
  MaxNestingLevel(),
  NumberOfParameters(),
  BooleanTrap(),
  SourceLinesOfCode(),
  MethodLength(),
  WidgetTreeDepth(),
];
