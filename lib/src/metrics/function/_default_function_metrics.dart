import '../metric.dart';
import 'cognitive_complexity.dart';
import 'cyclomatic_complexity.dart';
import 'halstead.dart';
import 'maintainability_index.dart';
import 'max_nesting_level.dart';
import 'method_length.dart';
import 'number_of_parameters.dart';
import 'source_lines_of_code.dart';

/// Set of function-level metrics enabled by default.
///
/// Order matters only for stable JSON output (the engine preserves it in the
/// emitted `values` map).
const List<FunctionMetric> defaultFunctionMetrics = [
  CyclomaticComplexity(),
  CognitiveComplexity(),
  HalsteadVolume(),
  HalsteadDifficulty(),
  HalsteadEffort(),
  MaintainabilityIndex(),
  MaxNestingLevel(),
  NumberOfParameters(),
  SourceLinesOfCode(),
  MethodLength(),
];
