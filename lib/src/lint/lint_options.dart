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
    this.flutter = true,
    this.test = true,
  });

  /// Defaults — every rule falls back to its compiled-in threshold.
  static const LintOptions defaults = LintOptions();

  final Map<String, num> warningThresholdById;

  /// Mirrors `dartrics: { flutter: true }` from `analysis_options.yaml`.
  /// Default `true`. The relaxations only trigger on classes that
  /// actually extend a known widget superclass, so non-Flutter packages
  /// are unaffected. Set to `false` to force the lenses on widget code.
  final bool flutter;

  /// Mirrors `dartrics: { test: true }` from `analysis_options.yaml`.
  /// Default `true`. When the file being analysed sits under `test/` or
  /// `integration_test/`, the size-and-shape rules step aside so AAA
  /// blocks and nested `group`/`setUp`/`test` scaffolding don't
  /// dominate the diagnostic stream.
  final bool test;

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
    return LintOptions(
      warningThresholdById: _parseThresholds(dartrics['metrics']),
      flutter: dartrics['flutter'] as bool? ?? true,
      test: dartrics['test'] as bool? ?? true,
    );
  }

  static Map<String, num> _parseThresholds(Object? node) {
    if (node is! YamlMap) return const {};
    final result = <String, num>{};
    for (final entry in node.entries) {
      final warning = _warningValue(entry.value);
      if (warning != null) result[entry.key.toString()] = warning;
    }
    return result;
  }

  /// Resolves the per-metric YAML value into a single `warning` scalar.
  /// Accepts either the long form `{ warning: <n> }` or the short form
  /// `<n>`; anything else (including `false` or unrelated keys) returns
  /// `null`, leaving the metric on its built-in default.
  static num? _warningValue(Object? raw) {
    if (raw is YamlMap) {
      final w = raw['warning'];
      return w is num ? w : null;
    }
    if (raw is num) return raw;
    return null;
  }
}
