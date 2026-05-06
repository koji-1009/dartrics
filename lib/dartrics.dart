/// Programmatic entry for embedding dartrics.
///
/// Exposes the metric calculator types and the analysis-report shapes used
/// by the CLI and by embedders. The analyzer-plugin entrypoint lives in
/// `lib/main.dart`; consumers of the plugin do not need anything from this
/// library.
library;

export 'src/metrics/function/cognitive_complexity.dart'
    show CognitiveComplexity;
export 'src/metrics/function/cyclomatic_complexity.dart'
    show CyclomaticComplexity;
export 'src/metrics/function/halstead.dart'
    show HalsteadCounts, HalsteadDifficulty, HalsteadEffort, HalsteadVolume;
export 'src/metrics/function/maintainability_index.dart'
    show MaintainabilityIndex;
export 'src/metrics/function/max_nesting_level.dart' show MaxNestingLevel;
export 'src/metrics/function/method_length.dart' show MethodLength;
export 'src/metrics/function/number_of_parameters.dart' show NumberOfParameters;
export 'src/metrics/function/source_lines_of_code.dart' show SourceLinesOfCode;
export 'src/metrics/metric.dart' show FunctionMetric, FunctionMetricInput;
export 'src/models/analysis_report.dart'
    show
        AnalysisReport,
        ExplainEntry,
        MetricRecord,
        MetricViolation,
        ScopeRef,
        ScopeKind,
        Severity;
export 'src/models/source_location.dart' show SourceLocation;
export 'src/models/unused_declaration.dart' show UnusedDeclaration, UnusedKind;
