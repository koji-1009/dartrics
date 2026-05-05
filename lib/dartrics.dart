/// Programmatic entrypoint for embedding dartrics.
///
/// The public surface is intentionally minimal during Phases 0–4. It will
/// stabilize at Phase 5 ahead of the first pub.dev release.
library;

export 'src/models/analysis_report.dart' show AnalysisReport, MetricRecord, MetricViolation, ScopeRef, ScopeKind, Severity;
export 'src/models/source_location.dart' show SourceLocation;
export 'src/models/unused_declaration.dart' show UnusedDeclaration, UnusedKind;
