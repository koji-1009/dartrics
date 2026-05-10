/// Programmatic entry for embedding dartrics — the function-level metric
/// calculators only.
///
/// `lib/main.dart` is the analyzer-plugin entrypoint; consumers of the
/// plugin do not need anything from this library.
///
/// Class- and library-level metrics, the report / regression / coverage
/// / dismissal / unused-detector model shapes, and `MetricEngine` itself
/// are intentionally **not** exported. The supported integration point
/// for those scopes is `dartrics analyze --reporter json`, parsed in
/// your own pipeline. This keeps the public Dart API tight enough that
/// internal evolution doesn't trigger breaking changes for consumers we
/// don't yet have. If you need a Dart-level handle on a shape that
/// isn't exported here, please file an issue describing the use case
/// before reaching into `package:dartrics/src/`.
library;

export 'src/metrics/function/cognitive_complexity.dart'
    show CognitiveComplexity;
export 'src/metrics/function/cyclomatic_complexity.dart'
    show CyclomaticComplexity;
export 'src/metrics/function/halstead.dart' show HalsteadCounts, HalsteadVolume;
export 'src/metrics/function/method_length.dart' show MethodLength;
export 'src/metrics/function/number_of_parameters.dart' show NumberOfParameters;
export 'src/metrics/function/source_lines_of_code.dart' show SourceLinesOfCode;
export 'src/metrics/metric.dart'
    show FunctionMetric, FunctionMetricInput, MetricPolarity;
export 'src/version.dart' show dartricsVersion;
