# dartrics

Dart code-quality metrics and unused public-API detection.

`dartrics` re-implements the academically-grounded metric suite (CK, Halstead, McCabe, Martin, Cognitive Complexity) on top of `package:analyzer`, and augments `dart analyze`'s `dead_code` lint with a Periphery-style public-API reachability pass.

## Status

Pre-alpha — landing the metric suite phase by phase ahead of the first pub.dev release. No public-API stability guarantees yet.

## Install

```bash
dart pub global activate dartrics
```

## Quick examples

```bash
# JSON for machine processing / jq pipelines
dartrics analyze lib/ --reporter json --output metrics.json

# Markdown for PR comments (formatted via package:dapper)
dartrics analyze lib/ --reporter md > report.md

# Token-efficient YAML-ish report optimized for LLM consumption
dartrics analyze lib/ --reporter ai | claude -p "閾値超過部分をリファクタしろ"

# SARIF 2.1.0 for GitHub Code Scanning / GitLab ingestion
dartrics analyze lib/ --reporter sarif --output dartrics.sarif

# Unused public-API detection only, used as a CI quality gate
dartrics unused lib/ --fatal-warnings

# Re-emit a previously saved JSON report in another format
dartrics report metrics.json --reporter md > report.md
```

## Provided metrics

### Function / method level

| Metric | Reference | Notes |
|---|---|---|
| Cyclomatic Complexity | McCabe 1976 | `1 + d` decision points; `if/for/while/do/switch case/&&/\|\|/?:/catch` |
| Cognitive Complexity | SonarSource 2018 | B1 control-flow + B2 nesting penalty + B3 logical-op sequences |
| Halstead Volume / Difficulty / Effort | Halstead 1977 | token-based n1/n2/N1/N2 classification |
| Maintainability Index | Oman 1992 | `171 − 5.2·ln(V) − 0.23·CC − 16.2·ln(LOC)`, clamped to `[0, 171]` |
| Maximum Nesting Level | — | depth of `if/for/while/do/switch/try/closure` blocks |
| Number Of Parameters | — | positional + named + optional |
| Source Lines Of Code | — | non-blank, non-comment-only lines |
| Method Length | — | total source lines spanned by the body |

### Class level

| Metric | Reference | Notes |
|---|---|---|
| Number Of Methods | — | members with non-empty bodies |
| Weighted Methods Per Class | CK 1994 | sum of cyclomatic complexity across methods |
| LCOM4 | Hitz & Montazeri 1995 | connected components in the field-share + method-call graph |
| Coupling Between Objects | CK 1994 | distinct other types referenced anywhere in the class |
| Response For a Class | CK 1994 | `\|methods ∪ method-names invoked from those methods\|` |
| Depth of Inheritance Tree | CK 1994 | length from this class to `Object` |
| Number Of Children | CK 1994 | direct subclasses found in the analysis root |
| Class Length | — | total source lines spanned by the class declaration |

### Library / file level

| Metric | Reference | Notes |
|---|---|---|
| Efferent Coupling (Ce) | Martin 1994 | distinct project-internal + `package:` dependencies (excludes `dart:*`) |
| Afferent Coupling (Ca) | Martin 1994 | incoming internal-import edges |
| Instability (I) | Martin 1994 | `Ce / (Ca + Ce)` |
| Abstractness (A) | Martin 1994 | abstract-class + mixin / total class-like declarations |
| Distance from Main Sequence (D) | Martin 1994 | `\|A + I − 1\|` |

## Public-API unused-code detection

Performs Periphery-style reachability analysis over a name-based reference graph, rooted at `main`, declarations annotated with `@pragma('vm:entry-point')`, and (when `excludeExported` is enabled) declarations under `lib/` outside `lib/src/`. The detector follows `export ... show ...` clauses so re-exported `lib/src/` symbols stay reachable. Reports unused public functions, classes, mixins, extensions, typedefs, enums, and top-level fields. Private (underscore-prefixed) names are intentionally skipped because `dart analyze`'s `dead_code` lint already covers them.

## Configuration

`dartrics` reads its settings from a `dartrics:` section in `analysis_options.yaml` (default; override with `--config <path>`). The Phase 6 `dartrics_lint` analyzer plugin reads from the same file, so the CLI and the IDE share thresholds.

```yaml
analyzer:
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"

dartrics:
  metrics:
    cyclomatic-complexity:
      warning: 10
      error: 20
    cognitive-complexity:
      warning: 15
    lcom4:
      warning: 2
    maximum-nesting-level:
      warning: 4
    number-of-parameters:
      warning: 4
      error: 8

  unused:
    entry-points:
      - "main"
      - "@pragma:vm:entry-point"
      - "test"
    exclude-exported: true
    ignore-annotations:
      - "visibleForTesting"
      - "protected"
      - "JsonSerializable"

  exclude:
    - "lib/generated/**"
```

## CLI

```
dartrics <command> [arguments]

Commands:
  analyze        compute every metric and run the unused detector
  unused         run only the public-API reachability detector
  report         re-emit a previously saved JSON report in another format

Common options:
  --config <path>          configuration file (default: analysis_options.yaml)
  --reporter <name>        console | json | md | ai | sarif (default: console)
  --output <path>          output destination; "-" means stdout (default: -)
  --root <path>            analysis root directory (default: cwd)
  --fatal-warnings         exit non-zero if any warning is reported
  --fatal-style            exit non-zero if any style violation is reported (reserved)
  -v, --verbose            FINE-level logging
```

### Exit codes (sysexits)

| Code | Constant | Meaning |
|---|---|---|
| 0 | `ExitCode.success` | clean run |
| 1 | — | violations detected (with `--fatal-warnings`) |
| 64 | `ExitCode.usage` | bad CLI arguments |
| 65 | `ExitCode.data` | input file invalid |
| 70 | `ExitCode.software` | internal error |
| 78 | `ExitCode.config` | configuration file invalid |

## Output formats

- **console** — human-friendly summary line + per-violation lines.
- **json** — stable schema for `jq` pipelines and SARIF transformation.
- **md** — Markdown for PR comments and issue bodies, finalised through `package:dapper`'s `formatMarkdown` for canonical formatting.
- **ai** — token-efficient YAML-ish report with one block per violation/unused entry plus a 7-line snippet window centred on the location, finalised through `formatYaml`.
- **sarif** — SARIF 2.1.0 envelope ingestible by GitHub Code Scanning / GitLab.

## Repository layout

```
dartrics/
├── bin/dartrics.dart              # minimal CLI entrypoint
├── lib/                           # core library (CLI + engine)
│   ├── dartrics.dart              # public exports
│   └── src/
│       ├── cli/                   # CommandRunner + subcommands
│       ├── config/                # YAML loader
│       ├── metrics/{function,class,library}/
│       ├── models/                # AnalysisReport, ScopeRef, …
│       ├── reporters/             # console, json, md, ai, sarif
│       └── unused/                # reachability graph + detector
├── packages/
│   └── dartrics_lint/             # analyzer-plugin companion package
├── test/                          # unit + integration tests (100% line coverage)
└── analysis_options.yaml          # strict lint config + (eventually) dartrics: thresholds
```

## Companion package

`packages/dartrics_lint/` ships the lightweight function-level diagnostics as a library that the analyzer-plugin entrypoint can consume. Heavier class- and library-level metrics plus the unused detector remain CLI-only. See [`packages/dartrics_lint/README.md`](packages/dartrics_lint/README.md).

## Development

```bash
dart pub get                              # at repo root
dart pub get -C packages/dartrics_lint    # plus the companion package
dart format lib test packages/dartrics_lint
dart analyze
dart test
dart pub run coverage:test_with_coverage  # 100% line coverage is required
```

See [`AGENTS.md`](AGENTS.md) for the AI-agent / contributor workflow notes.

## License

MIT.
