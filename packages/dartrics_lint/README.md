# dartrics_lint

Dart analyzer-plugin companion to [`dartrics`](../../) that surfaces lightweight function-level metric violations as IDE / CLI diagnostics.

## Status

Early. The diagnostic library (`diagnose()`) is implemented and unit-tested; the analyzer-plugin entrypoint that wires it into the analysis-server protocol is staged in a follow-up. Heavy metrics (LCOM4, CBO, RFC, library coupling) and the unused-public-API detector stay CLI-side because they need a project-wide index.

## Provided diagnostics

- `cyclomatic-complexity`
- `cognitive-complexity`
- `maximum-nesting-level`
- `number-of-parameters`

## Configuration

```yaml
# analysis_options.yaml
plugins:
  dartrics_lint: ^0.1.0
```

Configuration is taken from a programmatic `DartricsLintConfig` (the analyzer-plugin entrypoint will expose a YAML mirror of the same shape). Each rule has an `enabled` flag plus optional `warning` / `error` thresholds:

```dart
import 'package:dartrics_lint/dartrics_lint.dart';

const config = DartricsLintConfig(
  cyclomaticComplexity: RuleConfig(enabled: true, warning: 10, error: 20),
  cognitiveComplexity:  RuleConfig(enabled: true, warning: 15),
  maxNestingLevel:      RuleConfig(enabled: true, warning: 4),
  numberOfParameters:   RuleConfig(enabled: true, warning: 4, error: 8),
);
```

A value at or above `error` produces a `DiagnosticSeverity.error`; otherwise a value at or above `warning` produces a `DiagnosticSeverity.warning`. A `RuleConfig` with `enabled: false` is skipped entirely.

## Library usage

The plugin entrypoint and the dartrics CLI both go through the same `diagnose()` function:

```dart
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dartrics_lint/dartrics_lint.dart';

void main() {
  const source = 'int rate(int x) { ... }';
  final result = parseString(content: source);
  final diagnostics = diagnose(
    unit: result.unit,
    lineInfo: result.lineInfo,
    path: 'lib/example.dart',
    source: source,
  );
  for (final d in diagnostics) {
    print('${d.path}:${d.line}:${d.column} [${d.severity.name}] ${d.ruleId} — ${d.message}');
  }
}
```

`DartricsDiagnostic` is a flat record (`ruleId`, `severity`, `message`, `path`, `line`, `column`, `length`) suitable for translation into the analyzer-plugin protocol's `AnalysisError` shape.

## License

MIT.
