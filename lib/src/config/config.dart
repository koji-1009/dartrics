/// User-configurable thresholds and detection settings parsed from
/// `analysis_options.yaml`'s `dartrics:` section.
class Config {
  const Config({
    this.metricThresholds = const {},
    this.unused = const UnusedConfig(),
    this.exclude = const [],
    this.flutter = true,
    this.test = true,
    this.snapshot = const SnapshotConfig(),
    this.dismissals = const DismissalConfig(),
  });

  /// Map of `metric-id` → severity thresholds.
  final Map<String, MetricThresholds> metricThresholds;

  /// Settings for the unused-public-API detector.
  final UnusedConfig unused;

  /// Glob patterns excluded from analysis.
  final List<String> exclude;

  /// When `true`, dartrics relaxes a small set of metrics that fire
  /// noisily on idiomatic Flutter widgets (deeply-nested `build()` and
  /// constructors with many key/callback parameters). Default `true` —
  /// the relaxations only trigger when a class actually extends one of
  /// the known widget superclasses, so non-Flutter packages are
  /// unaffected. Set to `false` to force the lenses on widget code.
  final bool flutter;

  /// When `true`, dartrics relaxes the size-and-shape lenses on files
  /// living under `test/` or `integration_test/` (method/source length
  /// and max nesting at function level; class length and number of
  /// methods at class level). Cyclomatic / cognitive / boolean-trap
  /// stay engaged because a branchy test is still hard to read. Default
  /// `true`. Set to `false` to apply the production-grade thresholds to
  /// test files too.
  final bool test;

  /// Snapshot mode and path. Ships in `cache` mode by default — diffs
  /// are stored under `.dart_tool/dartrics/snapshot.json` (auto-ignored
  /// by `.gitignore` conventions).
  final SnapshotConfig snapshot;

  /// Configuration for the deliberate-dismissal channel. Disabled by
  /// default — both sources stay off until the user adds a
  /// `dismissals:` block to `analysis_options.yaml`.
  final DismissalConfig dismissals;
}

/// Default path the YAML sidecar is read from when [DismissalConfig.yamlPath]
/// is `null`. Resolved relative to the analysis root.
const String defaultDismissalsYamlPath = 'dartrics-dismissals.yaml';

/// Default minimum length (after trim) the `reason` text must reach to
/// be accepted when [DismissalConfig.requireReason] is on.
const int defaultDismissalMinReasonLength = 20;

/// Settings that govern how `// dartrics:dismiss` comments and the
/// `dartrics-dismissals.yaml` sidecar are parsed and validated.
///
/// Disabled by default — both [commentSource] and [yamlSource] are
/// `false` until the user opts in. The loader flips them to `true`
/// independently when the corresponding `sources:` keys appear under
/// `dartrics.dismissals`.
class DismissalConfig {
  const DismissalConfig({
    this.commentSource = false,
    this.yamlSource = false,
    this.requireReason = true,
    this.minReasonLength = defaultDismissalMinReasonLength,
    this.requireAuthor = false,
    this.requireTimestamp = false,
    this.warnStale = true,
    this.yamlPath,
  });

  /// Whether `// dartrics:dismiss …` comments are honoured.
  final bool commentSource;

  /// Whether the YAML sidecar file is loaded.
  final bool yamlSource;

  /// When true, an empty / missing reason rejects the dismissal and
  /// surfaces a stderr WARNING. When false, reasons are still preserved
  /// when present but never block a match.
  final bool requireReason;

  /// Minimum trimmed length the `reason` text must reach. Ignored when
  /// [requireReason] is false. Must be `>= 0`.
  final int minReasonLength;

  /// When true, YAML entries without `by:` are rejected.
  final bool requireAuthor;

  /// When true, YAML entries without `at:` are rejected.
  final bool requireTimestamp;

  /// When true, dismissals that never matched a live violation in the
  /// analyzed file set are surfaced as a stderr WARNING and as a
  /// `staleDismissals:` block in the AI report. Helps AI loops keep
  /// the dismiss file from accumulating dead entries when scopes are
  /// renamed / deleted or metrics drop below threshold. Default true;
  /// disable via `dartrics: { dismissals: { warnStale: false } }` for
  /// projects whose CI flow inspects the dismiss file separately.
  final bool warnStale;

  /// Optional override for the YAML sidecar path. `null` ⇒ defaults to
  /// [defaultDismissalsYamlPath] under the analysis root.
  final String? yamlPath;

  /// Convenience: any source enabled?
  bool get enabled => commentSource || yamlSource;
}

/// Mode of the per-run snapshot file used to drive AI / pre-commit
/// loops that want to see only what changed since the last analysis.
enum SnapshotMode {
  /// `.dart_tool/dartrics/snapshot.json` — gitignored by convention,
  /// stays local to each developer's machine.
  cache,

  /// `dartrics-snapshot.json` at the repo root — meant to be committed
  /// so CI can compare an open PR against the established baseline.
  baseline,

  /// Snapshot disabled. Useful in CI runs that only want to act on
  /// `--since <git-ref>` filtering.
  none,
}

class SnapshotConfig {
  const SnapshotConfig({this.mode = SnapshotMode.cache, this.path});

  final SnapshotMode mode;

  /// Optional override for the snapshot file path. When `null`, the
  /// path is derived from [mode]: `.dart_tool/dartrics/snapshot.json`
  /// for `cache`, `dartrics-snapshot.json` for `baseline`.
  final String? path;
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
    this.filter = const [],
  });

  final List<String> entryPoints;
  final bool excludeExported;
  final List<String> ignoreAnnotations;

  /// Narrows the kinds emitted by the resolved-AST detector to this
  /// allow-list. Empty means "every kind". Honours
  /// [UnusedKind.values] names — `function`, `method`, `klass`,
  /// `field`, `typedef`, `enumValue`, `extension`. Unknown names
  /// surface as a usage error from the CLI / config loader so a
  /// typo doesn't silently drop every entry.
  final List<String> filter;
}
