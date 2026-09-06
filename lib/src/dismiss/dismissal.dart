/// Where a dismissal entry was sourced from. Carried on every accepted
/// [MetricViolation] dismissal so reporters can show provenance and so
/// AI loops can decide which channel to amend.
enum DismissalSource {
  /// `// dartrics:dismiss <metric> reason="..."` adjacent to a Dart
  /// declaration.
  comment,

  /// `dartrics-dismissals.yaml` (or the path overridden via
  /// `dismissals.yamlPath`).
  yaml,
}

/// A single dismiss entry — either parsed from an in-source comment or
/// from the YAML sidecar. Owns enough context to be looked up by
/// `(file, scope, metricId)` and to carry validation metadata onward
/// to the report.
class Dismissal {
  const Dismissal({
    required this.file,
    required this.scope,
    required this.metricId,
    required this.reason,
    required this.source,
    this.by,
    this.at,
  });

  /// Absolute, normalised path of the file the dismissal targets. For
  /// comment dismissals this is the path the engine analysed the
  /// declaration under; for YAML dismissals the sidecar's `file:` value
  /// is resolved against the analysis root by [loadYamlDismissals].
  /// Absolute is the canonical form across the pipeline — `AnalyzerRunner`
  /// emits absolute paths, so `MetricRecord.file` is absolute and the
  /// [DismissalIndex] key must be too.
  final String file;

  /// Scope name (`Foo.bar` or `topLevelFn`) that must match
  /// [MetricRecord.scope.name].
  final String scope;

  /// Metric id (`cyclomatic-complexity`, `method-length`, …) that must
  /// match [MetricViolation.metricId].
  final String metricId;

  /// Free-form rationale. May be the empty string when the project has
  /// turned `requireReason` off; the validator decides whether that is
  /// acceptable.
  final String reason;

  /// Origin of this entry. Decides which validation rules apply (e.g.
  /// `requireAuthor` only meaningful for YAML).
  final DismissalSource source;

  /// Optional author. Only set for YAML entries that included `by:`.
  final String? by;

  /// Optional timestamp. Only set for YAML entries that included `at:`.
  final DateTime? at;
}
