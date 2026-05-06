import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'rules/boolean_trap_rule.dart';
import 'rules/cognitive_complexity_rule.dart';
import 'rules/cyclomatic_complexity_rule.dart';
import 'rules/maximum_nesting_level_rule.dart';
import 'rules/number_of_parameters_rule.dart';

/// dartrics analyzer plugin.
///
/// Surfaces the five lightweight function-level metric checks
/// (cyclomatic / cognitive complexity, maximum nesting level, number of
/// parameters, boolean-trap) as warnings inside `dart analyze` and
/// supported IDEs.
///
/// Heavier metrics (LCOM4, CBO, RFC, Martin coupling) and the
/// public-API unused detector remain CLI-only because they require a
/// project-wide index that an analysis-server plugin can't maintain
/// efficiently per-file.
class DartricsPlugin extends Plugin {
  @override
  String get name => 'dartrics';

  @override
  void register(PluginRegistry registry) {
    registry
      ..registerWarningRule(CyclomaticComplexityRule())
      ..registerWarningRule(CognitiveComplexityRule())
      ..registerWarningRule(MaximumNestingLevelRule())
      ..registerWarningRule(NumberOfParametersRule())
      ..registerWarningRule(BooleanTrapRule());
  }
}
