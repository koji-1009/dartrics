# dartrics

Dart code-quality metrics and unused public-API detection.

`dartrics` re-implements the academically-grounded metric suite (CK, Halstead, McCabe, Martin, Cognitive Complexity) on top of `package:analyzer`, and augments `dart analyze`'s `dead_code` lint with a Periphery-style public-API reachability pass.

## Status

`0.1.0` — first pub.dev release with both the CLI and the analyzer plugin. Public API is provisional through the `0.x` series.

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
dartrics analyze lib/ --reporter ai | claude -p "Refactor the threshold violations"

# Inject a metric's rationale + refactor hints alongside the violations
dartrics analyze lib/ --reporter ai --explain cyclomatic-complexity

# Catalogue every built-in metric (rationale + refactor hints)
dartrics rules --reporter ai

# SARIF 2.1.0 for GitHub Code Scanning / GitLab ingestion
dartrics analyze lib/ --reporter sarif --output dartrics.sarif

# Unused public-API detection only, used as a CI quality gate
dartrics unused lib/ --fatal-warnings

# Re-emit a previously saved JSON report in another format
dartrics report metrics.json --reporter md > report.md
```

## Provided metrics

dartrics ships a curated set; metrics that don't fit Dart's idioms (single inheritance, mixin/composition culture) are deliberately omitted, and metrics whose predictive value over CC has not held up empirically (Halstead V/D/E, Maintainability Index) ship **off by default** and must be opted into via `dartrics: { metrics: { <id>: { enabled: true } } }` in `analysis_options.yaml`.

### Function / method level

| Metric | Default | Reference | Notes |
|---|---|---|---|
| Cyclomatic Complexity | on | McCabe 1976 | `1 + d` decision points; `if/for/while/do/switch case/&&/\|\|/?:/catch` |
| Cognitive Complexity | on | SonarSource 2018 | B1 control-flow + B2 nesting penalty + B3 logical-op sequences |
| Maximum Nesting Level | on | — | depth of `if/for/while/do/switch/try/closure` blocks |
| Number Of Parameters | on | — | positional + named + optional |
| Source Lines Of Code | on | — | non-blank, non-comment-only lines |
| Method Length | on | — | total source lines spanned by the body |
| Halstead Volume / Difficulty / Effort | **off** | Halstead 1977 | token-based n1/n2/N1/N2 classification — historical |
| Maintainability Index | **off** | Oman 1992 | `171 − 5.2·ln(V) − 0.23·CC − 16.2·ln(LOC)`, clamped — composite, MS retired |

### Class level

| Metric | Default | Reference | Notes |
|---|---|---|---|
| Number Of Methods | on | — | members with non-empty bodies |
| Weighted Methods Per Class | on | CK 1994 | sum of cyclomatic complexity across methods |
| LCOM4 | on | Hitz & Montazeri 1995 | connected components in the field-share + method-call graph |
| Coupling Between Objects | on | CK 1994 | distinct other types referenced anywhere in the class |
| Response For a Class | on | CK 1994 | `\|methods ∪ method-names invoked from those methods\|` |
| Class Length | on | — | total source lines spanned by the class declaration |

DIT (Depth of Inheritance Tree) and NOC (Number of Children) from CK 1994 are **not provided**: Dart's mixin + composition-over-inheritance culture keeps single-inheritance chains shallow, so these metrics rarely produce signal in Dart projects.

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

## Analyzer plugin

`dartrics` ships its own analyzer plugin so the four lightweight function-level rules surface inline in `dart analyze` and the IDE.

```yaml
# analysis_options.yaml in your project
plugins:
  dartrics: ^0.1.0
```

After saving, restart the analysis server (in VS Code: "Dart: Restart Analysis Server"). The plugin enables four rules by default:

| Rule | Threshold (v0.1) |
|---|---|
| `dartrics_cyclomatic_complexity` | 10 |
| `dartrics_cognitive_complexity` | 15 |
| `dartrics_maximum_nesting_level` | 4 |
| `dartrics_number_of_parameters` | 4 |

Diagnostics surface at `info` severity in `dart analyze`. The current analyzer pipeline (`analysis_server_plugin 0.3.x` + `analyzer 13`) crashes the plugin isolate when a `LintCode` is constructed with anything other than `DiagnosticSeverity.INFO`, so the rules are pinned to INFO until that upstream constraint relaxes. The rules are still always-on; only the column prefix is fixed.

Heavier metrics (LCOM4, CBO, RFC, library coupling) and the public-API unused detector intentionally stay CLI-only because they require a project-wide index that an analysis-server plugin can't maintain efficiently per file.

### Customizing plugin thresholds

The plugin reads the same `dartrics:` section the CLI uses. Override any rule's threshold by setting its metric `id` under `metrics:`:

```yaml
plugins:
  dartrics: ^0.1.0

dartrics:
  metrics:
    cyclomatic-complexity:
      warning: 5            # default 10
    cognitive-complexity:
      warning: 8            # default 15
    maximum-nesting-level:
      warning: 3            # default 4
    number-of-parameters: 6 # default 4 — bare integer is treated as `warning:`
```

The CLI's `error:` field is also accepted and used by `dartrics analyze`; the plugin only consumes `warning:` because it emits a single severity (see the INFO-only note above). Restart the analysis server after changing thresholds.

## Configuration (CLI)

The `dartrics` CLI reads from a `dartrics:` section in `analysis_options.yaml` (default; override with `--config <path>`).

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
    # opt into a metric that's off by default:
    halstead-volume:
      enabled: true
      warning: 1000
    # bare-bool short form is also accepted:
    maintainability-index: true
    # disable a default-on metric:
    response-for-class: false

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
    presets:                    # opt-in code-gen keep-alive sets
      - freezed
      - json_serializable
      - dart_mappable
      - go_router_builder
      - auto_route

  exclude:
    - "lib/generated/**"
```

### Code-gen keep-alive presets

The `presets:` list expands to extra `ignoreAnnotations` so that classes annotated for popular code-generation packages aren't flagged as unused on a fresh checkout (before `dart run build_runner build`). Shipped presets and the annotations they cover:

| preset | annotations |
|---|---|
| `freezed` | `freezed`, `Freezed`, `unfreezed` |
| `json_serializable` | `JsonSerializable`, `JsonEnum` |
| `dart_mappable` | `MappableClass`, `MappableEnum`, `MappableLib` |
| `go_router_builder` | `TypedGoRoute`, `TypedShellRoute`, `TypedStatefulShellRoute` |
| `auto_route` | `RoutePage`, `AutoRouterConfig` |

Unknown preset names are silently ignored, so adding a preset never breaks an older dartrics version. Custom annotations beyond the presets stay in `ignore-annotations:`.

## CLI

```
dartrics <command> [arguments]

Commands:
  analyze        compute every metric and run the unused detector
  unused         run only the public-API reachability detector
  report         re-emit a previously saved JSON report in another format
  rules          list every metric with its rationale and refactor hints
  regression     compare metrics between two git states and surface the diff

Top-level options:
  --version                print the dartrics version and exit

Common options:
  --config <path>          configuration file (default: analysis_options.yaml)
  --reporter <name>        console | json | md | ai | sarif (default: console)
  --output <path>          output destination; "-" means stdout (default: -)
  --root <path>            analysis root directory (default: cwd)
  --since <ref>            restrict output to .dart files changed vs the
                           given git ref (e.g. main, HEAD~1, origin/main)
  --explain <metric-id>    inject the metric's rationale + refactor hints
                           into the report (repeatable)
  --snapshot <mode>        cache | baseline | none, or a custom path; overrides
                           the analysis_options.yaml setting
  --coverage <path>        attach lcov.info coverage to every violation;
                           defaults to coverage/lcov.info when present;
                           `--coverage none` to disable
  --fatal-warnings         exit non-zero if any warning is reported
  --fatal-style            exit non-zero if any style violation is reported (reserved)
  -v, --verbose            FINE-level logging
```

### Regression check (`dartrics regression`)

The `regression` subcommand re-runs every metric against two git states and emits a per-scope, per-metric diff classified as `improved` / `regressed` / `unchanged` / `added` / `removed`. It's the closing brace on the AI refactor loop: after the agent applies a fix, run `dartrics regression --before HEAD~1 --after HEAD --reporter ai` and check whether the change actually moved the metrics in the right direction.

```bash
# Default: compare last commit to working tree
dartrics regression

# Two commits, AI-friendly format, only one metric
dartrics regression --before main --after HEAD \
                    --metric cyclomatic-complexity --reporter ai
```

Each metric exposes a `MetricPolarity` (`down`, `up`, `neutral`) so the diff knows which direction is "healthier". CC, SLOC, LCOM4, etc. are `down`; maintainability index is `up`; Halstead and Martin-coupling metrics are `neutral` (delta surfaced but not classified).

A built-in heuristic flags refactors that look cosmetic — AI splitting one method into a swarm of one-line helpers without actually reducing complexity. When `tinyHelpersAdded ≥ 3 AND slocDelta > 4·helpers AND ccReduction < 2·helpers`, the AI / MD / console reporters surface a warning so the user notices.

### Coverage-aware violations (`--coverage`)

Pass `--coverage <path>` (or drop a `coverage/lcov.info` next to the package and dartrics will pick it up) to attach per-scope line and branch coverage to every emitted violation. The AI reporter then sorts by a priority key:

- **low coverage** → top of the list (most actionable: complex AND under-tested)
- **no coverage data** → middle (informational only)
- **high coverage** → near the bottom
- **`complexityJustified`** → last (see below)

For CC / Cognitive Complexity, dartrics adds a `complexityJustified: true` tag when the scope's branch coverage is `≥ 0.8` (or line coverage `≥ 0.95` when no `BRDA:` records exist). The intent is *earned complexity*: a function that's complex but exhaustively tested is probably complex on purpose, and AI loops should leave it alone unless the user disagrees.

### Snapshot diff mode

`dartrics analyze` and `dartrics unused` write a per-run snapshot of every analysed file's `sha256` and reuse it on the next invocation to emit only the records for files whose hash changed. The snapshot is git-independent, which makes it useful in three settings:

- AI loops that re-run after an automated refactor and only want to see the freshly-introduced violations.
- Pre-commit hooks where the working tree is dirty and `git diff` would be misleading.
- Non-git VCS (`jj`, `sapling`, …) where `--since` has no ref to compare against.

Three modes:

| Mode | Default path | When to use |
|---|---|---|
| `cache` (default) | `.dart_tool/dartrics/snapshot.json` | Local AI / dev loop. The path is git-ignored by Dart convention. |
| `baseline` | `dartrics-snapshot.json` (repo root) | Commit the snapshot so CI can compare a PR against the established baseline. |
| `none` | — | Disable snapshot diffing entirely (CI runs that only want `--since`). |

```yaml
dartrics:
  snapshot:
    mode: baseline
    # path: custom-snap.json   # optional override
```

The mode can also be flipped per-invocation: `--snapshot cache`, `--snapshot baseline`, `--snapshot none`, or `--snapshot <path>`. When `--since <ref>` is also supplied the git ref wins for filtering and the snapshot file is updated but not consulted.

### `--since` (diff mode)

`--since <ref>` keeps the analysis pipeline whole — every file is still resolved so cross-file metrics (LCOM4, library coupling, public-API reachability) stay accurate — but the emitted report is filtered down to declarations whose owning file changed between `<ref>` and `HEAD` according to `git diff --name-only --diff-filter=AMR <ref>...HEAD -- '*.dart'`.

```bash
# AI-driven PR review: send only the changed-file violations
dartrics analyze --since origin/main --reporter ai | claude -p "Refactor the threshold violations"

# CI quality gate on the diff
dartrics analyze --since origin/main --fatal-warnings

# Unused public-API check, scoped to the diff
dartrics unused --since HEAD~1
```

Renames surface as the new path. Untracked files are ignored (they're not part of `git diff`). When git is missing or the ref doesn't resolve, the command exits with `65 EX_DATAERR` and a one-line error.

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

## Flutter-aware mode

Setting `dartrics: { flutter: true }` in `analysis_options.yaml` (or in the plugin block) relaxes a small set of metrics on idiomatic Flutter widgets so AI refactor loops don't churn on healthy `build()` trees:

| Target | Effect |
|---|---|
| `Widget.build()` | `maximum-nesting-level` and `method-length` are skipped |
| Widget constructor | `number-of-parameters` is skipped |
| Other methods on the same widget | Measured normally |

Detection is AST-only — a class counts as a widget when it directly extends `StatelessWidget`, `StatefulWidget`, `State`, `ConsumerWidget`, `ConsumerStatefulWidget`, `HookWidget`, or `HookConsumerWidget`. Cyclomatic / cognitive complexity, SLOC, and the class- and library-level metrics still apply, because deep branching inside `build()` is still hard to read.

## AI report schema (v1)

The `--reporter ai` output is the primary integration point for AI tooling. The format is:

```yaml
# dartrics ai-report v1
explain:                   # optional, only present when --explain is used
  - metric: cyclomatic-complexity
    rationale: |
      ...one-paragraph rationale...
    refactorHints:
      - hint sentence
      - …
violations:
  - file: lib/foo.dart
    line: 42
    scope: Foo.bar
    metric: cyclomatic-complexity
    value: 12
    threshold: 10
    severity: warning
    snippet: |
      …7 lines centred on `line`…
unused:
  - file: lib/util.dart
    line: 88
    kind: function
    name: _legacyFormatter
    snippet: |
      …7 lines centred on `line`…
```

Stable contract:

- `# dartrics ai-report v1` header is present on every emission. Consumers can match on it to validate the format.
- The snippet block is a YAML literal (`|`) of up to 7 lines (`line ± 3`).
- Field names (`metric`, `severity`, `scope`, etc.) are stable through the `0.x` series. New fields may be added.
- Breaking changes (renames, removals, semantic shifts) trigger a new header, e.g. `# dartrics ai-report v2`.

The JSON reporter emits the same logical model plus an `analyzedFiles` list that backs the snapshot diff:

```json
{
  "version": "1.0",
  "analyzedFiles": [
    { "path": "lib/foo.dart", "sha256": "…" }
  ],
  "metrics": [...],
  "unused": [...]
}
```

`analyzedFiles` is JSON-only — the markdown / ai / sarif / console reporters omit it because the snapshot file is the source of truth for hash data.

## Repository layout

```
dartrics/
├── bin/dartrics.dart              # minimal CLI entrypoint
├── lib/
│   ├── dartrics.dart              # public exports for embedders
│   ├── main.dart                  # analyzer-plugin entrypoint (final plugin = ...)
│   └── src/
│       ├── cli/                   # CommandRunner + subcommands
│       ├── config/                # YAML loader
│       ├── lint/                  # analyzer plugin: DartricsPlugin + AnalysisRules
│       ├── metrics/{function,class,library}/
│       ├── models/                # AnalysisReport, ScopeRef, …
│       ├── reporters/             # console, json, md, ai, sarif
│       └── unused/                # reachability graph + detector
├── test/                          # unit + integration tests (100% line coverage)
└── analysis_options.yaml          # strict lint config
```

The CLI (`bin/dartrics.dart`) and the analyzer plugin (`lib/main.dart`) live in the same package and share `lib/src/`. Users get both with a single `dart pub global activate dartrics` and one `plugins:` line.

## Development

```bash
dart pub get
dart format lib test
dart analyze
dart test
dart pub run coverage:test_with_coverage  # 100% line coverage is required
```

See [`AGENTS.md`](AGENTS.md) for the AI-agent / contributor workflow notes.

## License

MIT.
