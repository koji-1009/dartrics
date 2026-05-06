/// User-configurable thresholds and detection settings parsed from
/// `analysis_options.yaml`'s `dartrics:` section.
class Config {
  const Config({
    this.metricThresholds = const {},
    this.unused = const UnusedConfig(),
    this.exclude = const [],
  });

  /// Map of `metric-id` → severity thresholds.
  final Map<String, MetricThresholds> metricThresholds;

  /// Settings for the unused-public-API detector.
  final UnusedConfig unused;

  /// Glob patterns excluded from analysis.
  final List<String> exclude;
}

class MetricThresholds {
  const MetricThresholds({this.warning, this.error});

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
