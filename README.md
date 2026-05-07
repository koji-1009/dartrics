# dartrics

Dart code-quality metrics and unused public-API detection, designed as the AI-loop counterpart of `dart analyze`.

`dartrics` re-implements the academically-grounded metric suite (CK, Halstead, McCabe, Martin, Cognitive Complexity) on top of `package:analyzer`, augments `dart analyze`'s `dead_code` lint with a Periphery-style public-API reachability pass, and ships a `--reporter ai` output plus a `regression` subcommand that gives AI agents a tight refactor loop: **see violations → understand them → fix → verify the fix actually improved things**.

## Install

```bash
dart pub global activate dartrics
```

## Quick start

```bash
# Token-efficient YAML-ish report optimised for LLM consumption.
dartrics analyze lib/ --reporter ai | claude -p "Refactor the threshold violations"

# Same, with rationale + refactor hints for one metric injected.
dartrics analyze lib/ --reporter ai --explain cyclomatic-complexity

# Catalogue every metric (rationale + refactor hints).
dartrics rules --reporter ai

# After the agent applies a fix: confirm metrics actually improved.
dartrics regression --before HEAD~1 --after HEAD --reporter ai

# Markdown for PR comments / issue bodies.
dartrics analyze lib/ --reporter md > report.md

# CI quality gate scoped to the diff.
dartrics analyze lib/ --since origin/main --fatal-warnings
```

## Subcommands

| Command | Purpose |
| --- | --- |
| `analyze` | Every metric + the public-API unused detector. |
| `unused` | Public-API reachability only (fast path). |
| `report <input.json>` | Re-emit a previously saved JSON report in another format. |
| `rules` | Catalogue every metric with its rationale and refactor hints. |
| `regression` | Compare metrics between two git states; classify each delta as improved / regressed / unchanged / added / removed. |
| `manual` | Print the AI-facing operator's manual (mirror of [`doc/manual.md`](doc/manual.md)). |
| `doctor` | Validate the `dartrics:` block in `analysis_options.yaml` — flags unknown metric ids, unknown presets, and threshold orderings inconsistent with the metric's polarity. |
| `explain <id>` | Reverse-lookup a violation by its stable 16-hex-char id and print its rationale + refactor hints. Reads JSON from stdin or `--input <path>`. |

```
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
  --strict-dismiss         ignore every `dartrics:dismiss` directive
                           (comment + YAML); useful in CI / final review
  --concurrency <n>        max files resolved in parallel (default: host
                           CPU count, clamped to 16)
  --fatal-warnings         exit non-zero if any warning is reported
  --fatal-style            exit non-zero if any style violation is reported (reserved)
  -v, --verbose            FINE-level logging
```

## Provided metrics

dartrics ships a curated set; metrics that don't fit Dart's idioms (single inheritance, mixin / composition culture) are deliberately omitted, and metrics whose predictive value over CC has not held up empirically (Halstead V/D/E, Maintainability Index) ship **off by default** and must be opted into via `dartrics: { metrics: { <id>: { enabled: true } } }`.

### Function / method level

| Metric                                | Default | Reference        | Notes                                                                       |
| ------------------------------------- | ------- | ---------------- | --------------------------------------------------------------------------- |
| Cyclomatic Complexity                 | on      | McCabe 1976      | `1 + d` decision points; `if/for/while/do/switch case/&&/\|\|/?:/catch`     |
| Cognitive Complexity                  | on      | SonarSource 2018 | B1 control-flow + B2 nesting penalty + B3 logical-op sequences              |
| Maximum Nesting Level                 | on      | —                | depth of `if/for/while/do/switch/try/closure` blocks                        |
| Number Of Parameters                  | on      | —                | positional + named + optional                                               |
| Boolean Trap                          | on      | McConnell 2004; Bloch 2018 | count of `bool`-typed parameters; default warning 2                       |
| Widget Tree Depth                     | **off** | —                | deepest chain of nested `InstanceCreationExpression`s in the body; default warning 7. Opt-in for Flutter projects via `dartrics: { metrics: { widget-tree-depth: { enabled: true } } }` |
| Source Lines Of Code                  | on      | —                | non-blank, non-comment-only lines                                           |
| Method Length                         | on      | —                | total source lines spanned by the body                                      |
| Halstead Volume / Difficulty / Effort | **off** | Halstead 1977    | token-based n1/n2/N1/N2 classification — historical                         |
| Maintainability Index                 | **off** | Oman 1992        | `171 − 5.2·ln(V) − 0.23·CC − 16.2·ln(LOC)`, clamped — composite, MS retired |

### Class level

| Metric                     | Reference             | Notes                                                       |
| -------------------------- | --------------------- | ----------------------------------------------------------- |
| Number Of Methods          | —                     | members with non-empty bodies                               |
| Weighted Methods Per Class | CK 1994               | sum of cyclomatic complexity across methods                 |
| LCOM4                      | Hitz & Montazeri 1995 | connected components in the field-share + method-call graph |
| Coupling Between Objects   | CK 1994               | distinct other types referenced anywhere in the class       |
| Response For a Class       | CK 1994               | `\|methods ∪ method-names invoked from those methods\|`     |
| Class Length               | —                     | total source lines spanned by the class declaration         |

DIT (Depth of Inheritance Tree) and NOC (Number of Children) from CK 1994 are **not provided**: Dart's mixin + composition-over-inheritance culture keeps single-inheritance chains shallow, so they rarely produce signal.

### Library / file level (Martin 1994)

| Metric                          | Notes                                                                   |
| ------------------------------- | ----------------------------------------------------------------------- |
| Efferent Coupling (Ce)          | distinct project-internal + `package:` dependencies (excludes `dart:*`) |
| Afferent Coupling (Ca)          | incoming internal-import edges                                          |
| Instability (I)                 | `Ce / (Ca + Ce)`                                                        |
| Abstractness (A)                | abstract-class + mixin / total class-like declarations                  |
| Distance from Main Sequence (D) | `\|A + I − 1\|`                                                         |

Each metric exposes `rationale`, `refactorHints`, and `polarity` (`down` / `up` / `neutral`) so AI agents can act on a violation without re-deriving the metric's intent and so the regression diff knows which direction is "healthier".

## AI integration

The CLI's `--reporter ai` is the primary integration point for AI tooling. The output is a token-efficient YAML-ish bundle starting with `# dartrics ai-report v1`. Two companion docs aimed at the AI consumer:

- [`doc/manual.md`](doc/manual.md) — operator's manual. Each metric framed as a lens on "hard to read", with the accept-or-reject decision step made explicit. Also reachable from inside an agent loop as `dartrics manual`, which prints the same content to stdout (the manual ships with the executable so `dart pub global activate dartrics` is enough — no separate doc download needed).
- [`doc/ai-loop.md`](doc/ai-loop.md) — end-to-end loop walkthrough (setup → propose → apply → verify) with sample prompts.

Eight flags compose into a tight refactor loop:

- **`--explain <metric-id>`** (repeatable) injects the metric's paragraph rationale and concrete refactor hints alongside the violations. The catalogue lives in `dartrics rules` so you can also feed it once and have agents reference it.
- **Auto-explain** (default on; `--no-auto-explain` to opt out) auto-attaches the rationale + refactorHints for every metric that produced at least one violation. Most loops never need the explicit `--explain` flag.
- **Stable violation `id`** — every violation carries a 16-hex-char `id = sha256("<file>|<scope>|<metric>")` so AI loops can correlate runs ("`a3f1c4e9…` showed up again ⇒ my fix didn't take"). Surfaces in the JSON / AI / md reporters and as `partialFingerprints.dartrics/v1` in SARIF.
- **`--limit <n>`** caps violations + unused entries shown by the AI / md reporters after the priority sort. Token-budget control for context-bounded agents; truncated entries are summarised in a `truncated:` block (AI) or `_+ N more_` line (md).
- **`--coverage <path>`** (auto-detects `coverage/lcov.info`) attaches per-scope line and branch coverage to every emitted violation. The reporter sorts by a priority key — low-coverage / high-severity entries land first, `complexityJustified` ones at the bottom.
- **`complexityJustified: true`** flags CC / Cognitive violations whose scope has branch coverage `≥ 0.8` (or line `≥ 0.95` when `BRDA:` records are absent). The intent is *earned complexity*: a function that's complex but exhaustively tested is probably complex on purpose, so AI loops should leave it alone.
- **Deliberate dismissal** lets agents (and humans) suppress a specific `(file, scope, metric)` triple — see [Deliberate dismissal](#deliberate-dismissal) below.
- **`--snapshot <mode>`** writes a per-file `sha256` after each run and emits only the records for files whose hash changed on the next invocation. Git-independent, so it works for AI loops, pre-commit hooks (dirty index), and non-git VCS (`jj`, `sapling`). `cache` (default) lands at `.dart_tool/dartrics/snapshot.json`; `baseline` at `dartrics-snapshot.json` for CI-shared baselines.
- **`--since <git-ref>`** filters the output to declarations whose owning `.dart` file changed between `<ref>` and `HEAD` (per `git diff --name-only --diff-filter=AMR`). Cross-file analysis stays accurate; only the *emitted* records are filtered.

### Deliberate dismissal

Suppress a specific violation when a refactor would actually hide intent. dartrics treats dismissals as a triaged-but-still-visible bucket: violations stay in the report, but `dismissed: true` (with the carried `reason`) tells AI loops to leave them alone. Two channels, both opt-in via `analysis_options.yaml`:

```yaml
dartrics:
  dismissals: {}                # bare block ⇒ both sources on, requireReason: true (≥20 chars)
```

```yaml
dartrics:
  dismissals:
    sources:
      comment: true             # // dartrics:dismiss …
      yaml: true                # dartrics-dismissals.yaml
    requireReason: true
    minReasonLength: 20
    requireAuthor: false        # YAML-only (`by:` field)
    requireTimestamp: false     # YAML-only (`at:` field)
    yamlPath: dartrics-dismissals.yaml
```

**Comment form** — sits immediately above the declaration; blank line invalidates it. Stack multiple lines for multiple metrics:

```dart
// dartrics:dismiss cyclomatic-complexity reason="State machine: splitting hides intent"
// dartrics:dismiss method-length reason="State machine: splitting hides intent"
int parse(Token start) { ... }
```

**YAML form** — `dartrics-dismissals.yaml` at the project root (or `yamlPath:`):

```yaml
version: 1
dismissals:
  - file: lib/parser.dart
    scope: parse
    metric: cyclomatic-complexity
    reason: "Recursive descent parser; splitting hides intent"
    by: claude-opus-4-7         # required when requireAuthor: true
    at: "2026-05-06T19:14:00Z"  # required when requireTimestamp: true
```

Hits flow through the validator. Reasons that fall short of `minReasonLength` keep the violation **live** and stamp it with `dismissalRejected: <why>` (plus a stderr WARNING) so the agent can amend the entry. YAML always beats a colliding comment with the same key. `--strict-dismiss` makes the engine ignore every dismissal for that run — useful in CI / final review when the operator wants to see the raw triage list.

### Regression check

After the agent applies a fix, run:

```bash
dartrics regression --before HEAD~1 --after HEAD --reporter ai
```

The diff is per-scope, per-metric, classified as `improved` / `regressed` / `unchanged` / `added` / `removed` according to each metric's `MetricPolarity`. A built-in heuristic (`tinyHelpersAdded ≥ 3 AND slocDelta > 4·helpers AND ccReduction < 2·helpers`) flags refactors that look cosmetic — AI splitting one method into a swarm of one-line helpers without actually reducing branching — so the user notices.

### `--since` (diff mode)

```bash
# AI-driven PR review: send only the changed-file violations.
dartrics analyze --since origin/main --reporter ai | claude -p "Refactor the threshold violations"

# CI quality gate scoped to the diff.
dartrics analyze --since origin/main --fatal-warnings
```

Renames surface as the new path. Untracked files are ignored. When git is missing or the ref doesn't resolve, the command exits with `65 EX_DATAERR`.

When `--since` and snapshot are both active, the git ref wins for filtering; the snapshot file is updated but not consulted.

## Configuration

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/koji-1009/dartrics/main/schemas/dartrics-config.schema.json
# analysis_options.yaml
analyzer:
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"

dartrics:
  flutter: true              # opt-in widget-aware skip rules

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
    halstead-volume:         # opt into a metric that's off by default
      enabled: true
      warning: 1000
    maintainability-index: true        # bare-bool short form
    response-for-class: false          # disable a default-on metric

  unused:
    entry-points: ["main", "@pragma:vm:entry-point", "test"]
    exclude-exported: true
    ignore-annotations:
      - "visibleForTesting"
      - "protected"
      - "JsonSerializable"
    # presets: kept for backward compat; every codegen preset is
    # always on as of 0.1.0, listing them here is no longer required.

  snapshot:
    mode: baseline           # cache | baseline | none

  exclude:
    - "lib/generated/**"
```

The `dartrics:` section is read by both the CLI and the analyzer plugin.

The leading `# yaml-language-server: $schema=…` directive turns on autocomplete + typo detection in editors that integrate with [yaml-language-server](https://github.com/redhat-developer/yaml-language-server) — VS Code (with the Red Hat YAML extension), JetBrains, Neovim, Helix. The schema also covers the `dismissals:` block; see [JSON Schema files](#json-schema-files) for the dismissal sidecar's own schema.

### Code-gen keep-alive annotations

Every codegen-related annotation listed here is **always** treated as a reachability root for the unused detector, so source classes that depend on a yet-to-be-generated `.g.dart` / `.freezed.dart` / `.config.dart` partner aren't flagged as unused on a fresh checkout (before `dart run build_runner build` has run). No opt-in is required:

| Package                                                       | Annotations                                                                                                                                |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| [freezed](https://pub.dev/packages/freezed)                   | `freezed`, `Freezed`, `unfreezed`                                                                                                          |
| [json_serializable](https://pub.dev/packages/json_serializable) | `JsonSerializable`, `JsonEnum`                                                                                                             |
| [dart_mappable](https://pub.dev/packages/dart_mappable)       | `MappableClass`, `MappableEnum`, `MappableLib`                                                                                             |
| [go_router_builder](https://pub.dev/packages/go_router_builder) | `TypedGoRoute`, `TypedShellRoute`, `TypedStatefulShellRoute`                                                                               |
| [auto_route](https://pub.dev/packages/auto_route)             | `RoutePage`, `AutoRouterConfig`                                                                                                            |
| [riverpod_generator](https://pub.dev/packages/riverpod_generator) | `riverpod`, `Riverpod`                                                                                                                     |
| [injectable](https://pub.dev/packages/injectable)             | `injectable`, `Injectable`, `singleton`, `Singleton`, `lazySingleton`, `LazySingleton`, `factoryMethod`, `FactoryMethod`, `module`, `Module`, `InjectableInit` |
| [hive](https://pub.dev/packages/hive) / [hive_ce](https://pub.dev/packages/hive_ce) | `HiveType`, `HiveField`                                                                                                                    |
| [drift](https://pub.dev/packages/drift)                       | `DriftDatabase`, `DriftAccessor`, `DataClassName`, `TableIndex`, `UseRowClass`                                                             |

The annotations are looked up by **simple name only** (`@Freezed()` matches via the simple name `Freezed`). If your project doesn't use a given package, the corresponding annotation never appears in source and the entry has no effect — there's no per-project cost to leaving every preset on.

The `dartrics: { unused: { presets: [...] } }` config field is still parsed for backward compatibility with older configs, but its value is ignored. If you need to keep additional annotations alive (e.g. an in-house codegen package), list them explicitly under `dartrics: { unused: { ignore-annotations: [...] } }`.

## Public-API unused-code detection

Periphery-style BFS reachability over a name-based reference graph, rooted at `main`, declarations annotated with `@pragma('vm:entry-point')`, and (when `excludeExported` is enabled) declarations under `lib/` outside `lib/src/`. The detector follows `export ... show ...` clauses so re-exported `lib/src/` symbols stay reachable. Reports unused public functions, classes, mixins, extensions, typedefs, enums, and top-level fields.

Private (underscore-prefixed) names are intentionally skipped — `dart analyze`'s `dead_code` lint already covers them.

Generated Dart files (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.config.dart`, `*.mocks.dart`, `*.pb*.dart`, `*.gen.dart`) are skipped during file collection; override with `AnalyzerRunner(includeGenerated: true)` if you really want metrics on them.

## Analyzer plugin

`dartrics` ships its own analyzer plugin so the four lightweight function-level rules surface inline in `dart analyze` and the IDE.

```yaml
# analysis_options.yaml in your project
plugins:
  dartrics: ^0.1.0
```

After saving, restart the analysis server (in VS Code: "Dart: Restart Analysis Server"). The plugin enables five rules by default:

| Rule                             | Default threshold |
| -------------------------------- | ----------------- |
| `dartrics_cyclomatic_complexity` | 10                |
| `dartrics_cognitive_complexity`  | 15                |
| `dartrics_maximum_nesting_level` | 4                 |
| `dartrics_number_of_parameters`  | 4                 |
| `dartrics_boolean_trap`          | 2                 |

Rule thresholds are read from the same `dartrics: { metrics: ... }` section the CLI uses; restart the analysis server after changes. The plugin honours `flutter: true` for the same skip rules as the CLI.

Diagnostics surface at `info` severity. The current analyzer pipeline (`analysis_server_plugin 0.3.x` + `analyzer 13`) crashes the plugin isolate when a `LintCode` is constructed with anything other than `DiagnosticSeverity.INFO`, so the rules are pinned to INFO until that upstream constraint relaxes — they're still always-on, only the column prefix is fixed.

Heavier metrics (LCOM4, CBO, RFC, library coupling) and the public-API unused detector intentionally stay CLI-only because they require a project-wide index that an analysis-server plugin can't maintain efficiently per file.

## Flutter-aware mode

`dartrics: { flutter: true }` is the default. Its job is to recognise idiomatic Flutter constructor signatures so the threshold-style lenses don't churn on widget code that's actually fine.

| Target                           | Effect                                                                  |
| -------------------------------- | ----------------------------------------------------------------------- |
| Widget constructor               | `number-of-parameters` is skipped (`key:` + a long callback list is the cultural norm) |
| `Widget.build()`                 | **Measured normally.** Control-flow nesting only counts `if/for/while/switch/try/closure`, so a healthy declarative tree gives 0; method length is informative even on declarative code |
| Other methods on the same widget | Measured normally                                                       |

Detection is AST-only — a class counts as a widget when it directly extends `StatelessWidget`, `StatefulWidget`, `State`, `ConsumerWidget`, `ConsumerStatefulWidget`, `HookWidget`, or `HookConsumerWidget`. Non-Flutter packages are unaffected because no class matches. Set `flutter: false` to force `number-of-parameters` on widget constructors too.

Visual depth from chained Widget literals (`Container(child: Container(...))`) is the responsibility of the separate `widget-tree-depth` lens, which is **off by default** and configurable independently. Opt in via `dartrics: { metrics: { widget-tree-depth: { enabled: true, warning: 7 } } }` — Flutter community practice is to extract a sub-widget once a build tree exceeds about 5–7 levels.

## Test-aware mode

`dartrics: { test: true }` is also the default. When the file under analysis sits under `test/` or `integration_test/` and its basename ends in `_test.dart`, the size-and-shape lenses step aside — arrange/act/assert blocks legitimately exceed `method-length` thresholds calibrated for production code, and nested `group(...)` / `setUp(...)` / `test(...)` scaffolding pushes `maximum-nesting-level` past 4 before any user logic begins. Set `test: false` to apply the production-grade thresholds to test files too.

| Scope             | Skipped on test files                                                |
| ----------------- | -------------------------------------------------------------------- |
| Function / method | `method-length`, `source-lines-of-code`, `maximum-nesting-level`     |
| Class             | `class-length`, `number-of-methods`                                  |

Cyclomatic complexity, cognitive complexity, number-of-parameters, boolean-trap, LCOM4 / CBO / RFC, and the library-level lenses still apply — branchy or tangled tests are still hard to read. Helpers in `test/` that don't end in `_test.dart` (e.g. `test/helpers.dart`) stay under the strict thresholds, since they're imported by tests rather than being tests themselves.

## AI report schema (v1)

```yaml
# dartrics ai-report v1
explain:                          # optional, only present when --explain is used
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
    coverage: 0.34              # only when --coverage is engaged
    branchCoverage: 0.20        # only when BRDA records exist
    complexityJustified: true   # only when set
    dismissed: true             # only when a dismissal accepted this violation
    dismissedFrom: yaml         # comment | yaml
    dismissReason: "…"          # carried verbatim from the dismissal
    dismissedBy: "claude-opus-4-7"   # YAML form only
    dismissedAt: "2026-05-06T19:14:00.000Z"  # YAML form only
    dismissalRejected: "…"      # mutually exclusive with `dismissed`; entry matched but failed validation
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
- Field names (`metric`, `severity`, `scope`, `coverage`, …) are stable through the `0.x` series. New fields may be added.
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

### JSON Schema files

Machine-checkable schemas live under [`schemas/`](schemas/):

- [`dartrics-report.schema.json`](schemas/dartrics-report.schema.json) — JSON reporter output (`dartrics analyze --reporter json`). Covers `version`, `analyzedFiles`, `metrics[].violations[]` (including the stable `id`, coverage, and dismissal fields), and `unused[]`.
- [`dartrics-dismissals.schema.json`](schemas/dartrics-dismissals.schema.json) — the YAML sidecar (`dartrics-dismissals.yaml`). Drop a `# yaml-language-server: $schema=…` directive at the top of your sidecar to get IDE autocomplete + validation:

  ```yaml
  # yaml-language-server: $schema=https://raw.githubusercontent.com/koji-1009/dartrics/main/schemas/dartrics-dismissals.schema.json
  version: 1
  dismissals: []
  ```

- [`dartrics-config.schema.json`](schemas/dartrics-config.schema.json) — the `dartrics:` block of `analysis_options.yaml` (metrics / unused / exclude / flutter / snapshot / dismissals). The example at the top of [Configuration](#configuration) wires it in.

All three schemas are draft-2020-12. Field additions are non-breaking; renames trigger a major version bump (`1` → `2` for the dismissals sidecar, `1.0` → `2.0` for the JSON report `version`).

## Output formats

- **console** — human-friendly summary line + per-violation lines.
- **json** — stable schema for `jq` pipelines and SARIF transformation.
- **md** — Markdown for PR comments and issue bodies, finalised through `package:dapper`'s `formatMarkdown`.
- **ai** — token-efficient YAML-ish report (see schema above).
- **sarif** — SARIF 2.1.0 envelope ingestible by GitHub Code Scanning / GitLab. `tool.driver.rules` is populated for every metric that fired in the run — `fullDescription` carries the rationale, `help.markdown` carries the refactor hints, `helpUri` deep-links back to the README anchor — so the platform shows the full lens explanation inline next to each result.

## Exit codes (sysexits)

| Code | Constant            | Meaning                                       |
| ---- | ------------------- | --------------------------------------------- |
| 0    | `ExitCode.success`  | clean run                                     |
| 1    | —                   | violations detected (with `--fatal-warnings`) |
| 64   | `ExitCode.usage`    | bad CLI arguments                             |
| 65   | `ExitCode.data`     | input file invalid                            |
| 70   | `ExitCode.software` | internal error                                |
| 78   | `ExitCode.config`   | configuration file invalid                    |

## Embedding

`lib/dartrics.dart` is intentionally tight — it exposes only the function-level metric calculators so a custom CI bot or editor extension can compute one metric on a parsed `CompilationUnit` without spinning up the full engine. Everything else (report shapes, regression diff, coverage attachment, dismissal, the unused detector, class- and library-level metrics, `MetricEngine` itself) is CLI-only in 0.1.0; the supported integration point is `dartrics analyze --reporter json` parsed in your own pipeline.

| What you get | Names |
| --- | --- |
| Function-level metric calculators | `CyclomaticComplexity`, `CognitiveComplexity`, `MaxNestingLevel`, `NumberOfParameters`, `BooleanTrap`, `MethodLength`, `SourceLinesOfCode`, `HalsteadCounts` / `HalsteadVolume` / `HalsteadDifficulty` / `HalsteadEffort`, `MaintainabilityIndex` |
| Calculator interface | `FunctionMetric`, `FunctionMetricInput`, `MetricPolarity` |
| Version string | `dartricsVersion` |

The library is deliberately *not* in charge of report assembly, regression diff, dismiss validation, snapshot persistence, or unused-API detection. Those features all ship through the CLI; their on-wire format is the JSON reporter, documented under [JSON Schema files](#json-schema-files). Reaching into `package:dartrics/src/` is unsupported — internals shift between minor versions. If a use case warrants exposing additional shapes, please file an issue describing the use case so the surface grows incrementally and keeps its stability commitment realistic.

`example/main.dart` shows a 30-line standalone embedding against `CyclomaticComplexity`.

## Recommendation

`dartrics` 0.1.0 is **recommended for AI-driven Dart codebases** — projects where Claude Code, Cursor, Codex, or another agent is doing meaningful code review or refactor work and the maintainer wants the agent's quality judgements to be grounded in reproducible, citation-backed metrics rather than vibes.

What's wired up for that use case:

- **Resolution** — every violation carries its threshold, severity, scope coverage, branch coverage, `complexityJustified` tag, and (where applicable) `dismissed` / `dismissalRejected` state. The `--reporter ai` YAML is sorted so the most actionable items come first.
- **Stability** — every violation has a 16-hex stable `id` so AI loops can correlate runs ("same id appeared again ⇒ my last refactor missed it"). Three published JSON Schemas (config / report / dismissals) cover the on-disk and on-wire surfaces. `# dartrics ai-report v1` is a contractual header.
- **Actionability** — `--explain` (now with auto-explain default-on) inlines the metric's rationale and refactor hints. Each metric exposes a `polarity` so the regression diff knows which direction is "healthier". The dismiss channel turns "I don't agree with this metric here" into a tracked, validated, auditable decision instead of a silent disable.
- **Noise control** — `--snapshot` / `--since` / `--limit` / `--strict-dismiss` compose into a noise floor that AI loops can actually live with; `--strict-dismiss --fatal-warnings` makes a clean CI gate.

- AI-facing reference: [`doc/manual.md`](doc/manual.md).
- End-to-end walkthrough with sample prompts: [`doc/ai-loop.md`](doc/ai-loop.md).

### Honest limitations

- **0.1.0 is the first release.** Field names are stable through the 0.x series, but the surface has not yet been stress-tested by external users; pin a version in CI.
- **The analyzer plugin covers only the five function-level rules** (CC, Cognitive, Max nesting, Number of parameters, Boolean-trap). LCOM4 / CBO / RFC / library coupling and the unused detector are CLI-only because they need a project-wide index that the analyzer-plugin API can't maintain efficiently per-file.
- **Cross-run memory is out of scope.** dartrics doesn't remember "this dismiss was rejected last iteration; don't propose it again." Stay session-local.
- **Performance is modest.** `--concurrency` parallelises file resolution but the analyzer driver itself is single-isolate; expect ~10 % wall-time wins on small trees, more on large ones. CPU-bound.
- **`package:analyzer` 13.x moves fast.** Major Dart SDK or analyzer bumps may require dartrics updates before they ship cleanly.
- **Built-in metric set is not exhaustive.** The catalogue deliberately omits metrics whose predictive value over CC has not held up empirically (DIT, NOC) and ships Halstead V/D/E + Maintainability Index off-by-default. Bring your own opt-in.

### Who should not adopt 0.1.0 yet

- Teams that need **per-line metric thresholds** in the IDE for the full metric suite — the plugin is intentionally narrow.
- Teams that don't engage with the dismiss channel at all — the validator is opinionated, and a pure-fail-fast linter (`dart analyze` + `--fatal-warnings`) is a better fit.
- Teams using Dart < 3.10 or analyzer < 13.

## Development

```bash
dart pub get
dart format lib test example
dart analyze
dart test
dart pub run coverage:test_with_coverage  # 100% line coverage is required
```

See [`AGENTS.md`](AGENTS.md) for the contributor / AI-agent workflow notes.

### Bundled Claude Code skill

`.claude/skills/dart-cli-app-best-practices/` is a verbatim copy of the [`dart-cli-app-best-practices`](https://github.com/kevmoo/dash_skills) skill from [kevmoo/dash_skills](https://github.com/kevmoo/dash_skills) (Apache-2.0). It informs the CLI entrypoint conventions used in `bin/` and `lib/src/entry_point.dart` — keep it in sync upstream when refactoring.

## License

MIT for dartrics itself; the bundled skill in `.claude/skills/` is Apache-2.0 (see its `SKILL.md` frontmatter).
