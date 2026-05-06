import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:yaml/yaml.dart';

/// Threshold overrides parsed from `analysis_options.yaml`'s `dartrics:`
/// section, keyed by the metric calculator's `id` (e.g.
/// `cyclomatic-complexity`).
///
/// The schema mirrors the CLI's: each metric may carry a `warning:` field,
/// which is the threshold the plugin compares the metric value against. The
/// CLI also accepts an `error:` field, but the plugin emits only one
/// severity (see the Phase 6 §F note in the CHANGELOG / e2e log) so it
/// reads `warning:` only.
///
/// ```yaml
/// dartrics:
///   metrics:
///     cyclomatic-complexity:
///       warning: 5
///     number-of-parameters: 6   # short form: bare integer is treated as warning
/// ```
class LintOptions {
  const LintOptions({
    this.warningThresholdById = const {},
    this.flutter = false,
  });

  /// Defaults — every rule falls back to its compiled-in threshold.
  static const LintOptions defaults = LintOptions();

  final Map<String, num> warningThresholdById;

  /// Mirrors `dartrics: { flutter: true }` from `analysis_options.yaml`.
  /// When true, the rules skip noisy widget-specific patterns (deeply
  /// nested `build()`, parameter-heavy widget constructors).
  final bool flutter;

  /// Returns the user-configured threshold for [metricId], or [fallback].
  num thresholdFor(String metricId, num fallback) {
    return warningThresholdById[metricId] ?? fallback;
  }

  /// Reads the project's `analysis_options.yaml` from
  /// `RuleContext.package.root` and parses the `dartrics:` section. Returns
  /// [defaults] when the file is missing or the section is absent /
  /// malformed.
  static LintOptions load(RuleContext context) {
    final root = context.package?.root;
    if (root == null) return defaults;
    final file = root.getChildAssumingFile('analysis_options.yaml');
    if (!file.exists) return defaults;
    final String content;
    try {
      content = file.readAsStringSync();
    } on Object {
      return defaults;
    }
    return parse(content);
  }

  /// Parses the `dartrics:` section out of an `analysis_options.yaml`
  /// content string. Exposed for testability.
  static LintOptions parse(String content) {
    final Object? root;
    try {
      root = loadYaml(content);
    } on YamlException {
      return defaults;
    }
    if (root is! YamlMap) return defaults;
    final dartrics = root['dartrics'];
    if (dartrics is! YamlMap) return defaults;
    final flutter = dartrics['flutter'] as bool? ?? false;
    final metrics = dartrics['metrics'];
    final result = <String, num>{};
    if (metrics is YamlMap) {
      for (final entry in metrics.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is YamlMap) {
          final warning = value['warning'];
          if (warning is num) result[key] = warning;
        } else if (value is num) {
          result[key] = value;
        }
      }
    }
    return LintOptions(warningThresholdById: result, flutter: flutter);
  }
}
