/// Lightweight diagnostic record emitted by the dartrics analyzer plugin.
///
/// The plugin entrypoint translates this into the analyzer-plugin
/// protocol's `AnalysisError` shape; CLI and tests can consume it directly
/// without the protocol overhead.
class DartricsDiagnostic {
  const DartricsDiagnostic({
    required this.ruleId,
    required this.severity,
    required this.message,
    required this.path,
    required this.line,
    required this.column,
    required this.length,
  });

  final String ruleId;
  final DiagnosticSeverity severity;
  final String message;
  final String path;
  final int line;
  final int column;
  final int length;
}

enum DiagnosticSeverity { warning, error }
