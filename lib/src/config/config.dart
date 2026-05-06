/// User-configurable thresholds and detection settings parsed from
/// `analysis_options.yaml`'s `dartrics:` section.
class Config {
  const Config({
    this.metricThresholds = const {},
    this.unused = const UnusedConfig(),
    this.exclude = const [],
    this.flutter = false,
  });

  /// Map of `metric-id` → severity thresholds.
  final Map<String, MetricThresholds> metricThresholds;

  /// Settings for the unused-public-API detector.
  final UnusedConfig unused;

  /// Glob patterns excluded from analysis.
  final List<String> exclude;

  /// When `true`, dartrics relaxes a small set of metrics that fire
  /// noisily on idiomatic Flutter widgets (deeply-nested `build()` and
  /// constructors with many key/callback parameters). Off by default
  /// for non-Flutter packages.
  final bool flutter;
}

class MetricThresholds {
  const MetricThresholds({this.enabled, this.warning, this.error});

  /// Override the metric's [FunctionMetric.defaultEnabled]. `null` means
  /// "use the metric's own default."
  final bool? enabled;
  final num? warning;
  final num? error;
}

class UnusedConfig {
  const UnusedConfig({
    this.entryPoints = const ['main', '@pragma:vm:entry-point', 'test'],
    this.excludeExported = true,
    this.ignoreAnnotations = const [
      'visibleForTesting',
      'protected',
      'JsonSerializable',
    ],
    this.presets = const [],
  });

  final List<String> entryPoints;
  final bool excludeExported;
  final List<String> ignoreAnnotations;

  /// Opt-in keep-alive annotation presets for popular code-generation
  /// packages (`freezed`, `json_serializable`, `dart_mappable`,
  /// `go_router_builder`, `auto_route`). See `keep_alive_presets.dart`
  /// for the contents shipped with each preset.
  final List<String> presets;
}
