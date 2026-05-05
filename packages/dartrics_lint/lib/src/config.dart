/// Per-rule on/off configuration for `dartrics_lint`.
///
/// Mirrors the `dartrics_lint:` section of `analysis_options.yaml`.
/// Defaults follow the design's recommendation: cheap function-level
/// metrics are on by default, expensive cross-class / project-wide ones
/// stay off and remain available through the CLI.
class DartricsLintConfig {
  const DartricsLintConfig({
    this.cyclomaticComplexity = const RuleConfig(enabled: true, warning: 10, error: 20),
    this.cognitiveComplexity = const RuleConfig(enabled: true, warning: 15),
    this.maxNestingLevel = const RuleConfig(enabled: true, warning: 4),
    this.numberOfParameters = const RuleConfig(enabled: true, warning: 4, error: 8),
  });

  final RuleConfig cyclomaticComplexity;
  final RuleConfig cognitiveComplexity;
  final RuleConfig maxNestingLevel;
  final RuleConfig numberOfParameters;
}

class RuleConfig {
  const RuleConfig({this.enabled = true, this.warning, this.error});
  final bool enabled;
  final num? warning;
  final num? error;
}
