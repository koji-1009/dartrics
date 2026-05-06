import '../reporters/rules_reporter.dart';
import 'class/default_class_metrics.dart';
import 'function/default_function_metrics.dart';
import 'library/default_library_metrics.dart';

/// Built-in default thresholds, mirroring the values baked into the
/// analyzer-plugin rule classes. Keeping them here means the `dartrics
/// rules` catalogue and the SARIF rules section stay in sync without
/// forcing the lint package onto embedders that only want the CLI
/// metrics.
const Map<String, num> defaultMetricThresholds = {
  'cyclomatic-complexity': 10,
  'cognitive-complexity': 15,
  'maximum-nesting-level': 4,
  'number-of-parameters': 4,
  'boolean-trap': 2,
};

/// Aggregates every default metric calculator into a list of
/// [RuleDescription]s — one per (function / class / library) metric.
/// The order tracks the registration order in the corresponding
/// `default_*_metrics.dart` lists, which is what the JSON / SARIF /
/// rules reporters surface to consumers.
List<RuleDescription> collectRuleDescriptions() {
  return [
    for (final m in defaultFunctionMetrics)
      RuleDescription(
        id: m.id,
        scope: 'function',
        defaultEnabled: m.defaultEnabled,
        defaultThreshold: defaultMetricThresholds[m.id],
        rationale: m.rationale,
        refactorHints: m.refactorHints,
      ),
    for (final m in defaultClassMetrics)
      RuleDescription(
        id: m.id,
        scope: 'class',
        defaultEnabled: m.defaultEnabled,
        defaultThreshold: defaultMetricThresholds[m.id],
        rationale: m.rationale,
        refactorHints: m.refactorHints,
      ),
    for (final m in defaultLibraryMetrics)
      RuleDescription(
        id: m.id,
        scope: 'library',
        defaultEnabled: m.defaultEnabled,
        defaultThreshold: defaultMetricThresholds[m.id],
        rationale: m.rationale,
        refactorHints: m.refactorHints,
      ),
  ];
}

/// Returns the [RuleDescription] for [metricId], or `null` if it is not
/// among the built-in metrics. Used by the `--explain` flow and by the
/// SARIF reporter when populating `tool.driver.rules`.
RuleDescription? findRuleDescription(String metricId) {
  for (final r in collectRuleDescriptions()) {
    if (r.id == metricId) return r;
  }
  return null;
}
