# dartrics_lint

Dart analyzer plugin that surfaces dartrics's lightweight function-level
metric violations as IDE/CLI diagnostics.

## Status

Early — the diagnostic library is implemented and unit-tested; the
analyzer-plugin entrypoint that wires it into the analysis-server protocol
is being staged in a follow-up.

## Configuration

```yaml
analyzer:
  plugins:
    - dartrics_lint

dartrics_lint:
  diagnostics:
    cyclomatic-complexity: true   # cheap, default on
    cognitive-complexity: true
    max-nesting-level: true
    number-of-parameters: true
    lcom4: false                  # heavy, default off — use the CLI
    cbo: false                    # heavy, default off — use the CLI
    unused-public-api: false      # CLI-only
```
