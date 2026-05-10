# dartrics

[![pub package](https://img.shields.io/pub/v/dartrics.svg)](https://pub.dev/packages/dartrics)
[![GitHub license](https://img.shields.io/github/license/koji-1009/dartrics)](https://github.com/koji-1009/dartrics/blob/main/LICENSE)
[![CI](https://github.com/koji-1009/dartrics/actions/workflows/analyze.yaml/badge.svg)](https://github.com/koji-1009/dartrics/actions/workflows/analyze.yaml)
[![codecov](https://codecov.io/gh/koji-1009/dartrics/branch/main/graph/badge.svg)](https://codecov.io/gh/koji-1009/dartrics)

Dart code-quality metrics and unused public-API detection, designed as the AI-loop counterpart of `dart analyze`.

## What it does

dartrics computes a battery of code-quality metrics — McCabe, Cognitive Complexity (Sonar), Chidamber & Kemerer, Martin, Halstead — on top of `package:analyzer`, alongside an analyzer-element BFS for unreachable public API à la Periphery. Every report mode is shaped to be *consumed*: `--reporter ai` ships a token-efficient YAML-ish bundle, sorted by actionability, with each metric's rationale, refactor hints, and primary-source citation embedded inline.

The wager: the academic catalogue is reusable now in a way it wasn't before — not because the metrics changed, but because the consumer did. Humans cannot compute LCOM4 by eye; the number alone doesn't tell you what to change; even when it does, the refactor isn't free. An AI loop absorbs all three costs. The CLI computes in milliseconds, auto-explain ships the rationale alongside every violation, the agent does the edit, and `dartrics regression` confirms the metric actually settled.

Each metric is treated as a **lens**: one specific dimension of "hard to read", anchored to its original paper. Lenses are independent — a function can be clean by cyclomatic complexity and tangled by cognitive complexity. dartrics does not gate; it surfaces what each lens reads, and leaves the accept / refactor / dismiss decision in the loop.

### Designed for the AI loop

- **Auto-explain by default** — rationale, refactor hints, and the primary-source citation ride alongside every fired metric, so an agent reads the *why* without a second tool call.
- **Coverage-aware reading** — `complexityJustified` exempts well-tested complex code (branch ≥ 0.8 / line ≥ 0.95) from the threshold list; violations sort by coverage so low-tested entries land first.
- **Stable IDs with reverse lookup** — every violation carries a 16-hex-char id; `dartrics explain <id> --input report.json` reverse-looks up the full context for a saved report. The same id reappears across runs so AI loops can detect "my fix didn't take".
- **Output stability** — every emission starts with a contractual header (`# dartrics ai-report v1`, `version: "1.0"`); field renames or removals bump the header so consumers can pin to it before parsing.
- **Docs in the binary** — `dartrics manual` and `dartrics ai-loop` print the operator's manual ([`doc/manual.md`](doc/manual.md)) / four-station walkthrough ([`doc/ai-loop.md`](doc/ai-loop.md)); `dart pub global activate dartrics` is enough, no separate doc download.

## Install

```bash
dart pub global activate dartrics
```

## Quick start

```bash
# Token-efficient YAML-ish report optimised for LLM consumption.
dartrics analyze lib/ --reporter ai | claude -p "Refactor the threshold violations"

# Catalogue every metric (rationale + refactor hints + references).
dartrics rules --reporter ai

# Reverse-lookup a violation by its 16-hex stable id.
dartrics explain a3f1c4e9b2d70218 --input report.json

# After the agent applies a fix: confirm metrics actually improved.
dartrics regression --before HEAD~1 --after HEAD --reporter ai

# CI quality gate scoped to the diff.
dartrics analyze lib/ --since origin/main --fatal-warnings

# In-binary references.
dartrics manual          # the operator's manual
dartrics ai-loop         # the setup → propose → apply → verify walkthrough
```

## Subcommands

| Command | Purpose |
| --- | --- |
| `analyze` | Every metric + the public-API unused detector. |
| `unused` | Public-API reachability only (fast path). |
| `report <input.json>` | Re-emit a previously saved JSON report in another format. |
| `rules` | Catalogue every metric with its rationale, refactor hints, and references. |
| `regression` | Compare metrics between two git states; classify each delta as improved / regressed / unchanged / added / removed. |
| `manual` | Print the AI-facing operator's manual (mirror of [`doc/manual.md`](doc/manual.md)). |
| `ai-loop` | Print the AI-loop walkthrough (mirror of [`doc/ai-loop.md`](doc/ai-loop.md)). |
| `doctor` | Validate the `dartrics:` block in `analysis_options.yaml` — flags unknown metric ids and threshold orderings inconsistent with the metric's polarity. |
| `explain <id>` | Reverse-lookup a violation by its stable 16-hex-char id and print its rationale + refactor hints + references. Reads JSON from stdin or `--input <path>`. |

```
Common options:
  --config <path>          configuration file (default: analysis_options.yaml)
  --reporter <name>        console | json | md | ai | sarif (default: console)
  --output <path>          output destination; "-" means stdout (default: -)
  --root <path>            analysis root directory (default: cwd)
  --since <ref>            restrict output to .dart files changed vs the
                           given git ref (e.g. main, HEAD~1, origin/main)
  --[no-]auto-explain      auto-attach rationale + refactor hints for every
                           metric that fired (default: enabled)
  --snapshot <mode>        cache | baseline | none, or a custom path
  --coverage <path>        attach lcov.info coverage to every violation;
                           defaults to coverage/lcov.info when present
  --strict-dismiss         ignore every dismiss directive (comment + YAML)
  --concurrency <n>        max files resolved in parallel (default: host
                           CPU count, clamped to 16)
  --limit <n>              cap violations + unused entries shown by the ai
                           and md reporters (after the priority sort)
  --fatal-warnings         exit non-zero if any warning is reported
  -v, --verbose            FINE-level logging
```

## Provided metrics

dartrics ships a curated set. Metrics that don't fit Dart's idioms (DIT, NOC; Dart's mixin + composition culture keeps inheritance chains shallow) are omitted; metrics whose value duplicates a simpler signal — Halstead Volume (predictive value over cyclomatic complexity has not held up empirically) and Method Length (highly correlated with SLOC in production code) — ship **off by default** and must be opted in via `dartrics: { metrics: { <id>: { enabled: true } } }`. Halstead Difficulty / Effort and the Maintainability Index are intentionally absent — both are pure derivations of `(n₁, n₂, N₁, N₂)` and `CC + V + LOC` respectively, so they add no orthogonal signal.

Each metric exposes `rationale`, `refactorHints`, `references` (the primary source — McCabe 1976, Hitz & Montazeri 1995, Martin 1994, …), and `polarity` (`down` / `neutral`). All four surface through `dartrics rules`, `dartrics explain <id>`, and the AI / md / SARIF reporters so an agent can verify a metric against its original paper rather than paraphrasing from training data.

### Function / method level

| Metric                                | Default | Reference        | Notes                                                                       |
| ------------------------------------- | ------- | ---------------- | --------------------------------------------------------------------------- |
| Cyclomatic Complexity                 | on      | McCabe 1976      | `1 + d` decision points; `if/for/while/do/switch case/&&/\|\|/?:/catch`. **Sealed-aware**: a `switch` whose subject is a sealed class doesn't count its case arms — the compiler enforces exhaustiveness. |
| Cognitive Complexity                  | on      | SonarSource 2018 | B1 control-flow + B2 nesting penalty + B3 logical-op sequences              |
| Maximum Nesting Level                 | on      | NIST SP 500-235  | depth of `if/for/while/do/switch/try/closure` blocks                        |
| Number Of Parameters                  | on      | Fowler 1999      | positional only — named parameters carry their name at the call site, dissolving the position-counting load Fowler's lens targets. Default warning 4 |
| Boolean Trap                          | on      | McConnell 2004; Bloch 2008 | count of *positional* `bool`-typed parameters; default warning 2  |
| Source Lines Of Code                  | on      | Boehm 1981       | non-blank, non-comment-only lines                                           |
| Method Length                         | **off** | Beck 1996        | total source lines spanned by the body. Off by default — high correlation with SLOC in production code |
| Halstead Volume                       | **off** | Halstead 1977    | `N · log₂(η)` — token-based program "size" |

### Class level

| Metric                     | Reference             | Notes                                                       |
| -------------------------- | --------------------- | ----------------------------------------------------------- |
| Number Of Methods          | Lorenz & Kidd 1994; CK 1994   | members with non-empty bodies. Equivalent to WMC with uniform weight=1 |
| Weighted Methods Per Class | CK 1994                       | sum of cyclomatic complexity across methods                            |
| LCOM4                      | Hitz & Montazeri 1995         | connected components in the field-share + method-call graph            |
| Coupling Between Objects   | CK 1994                       | distinct other types referenced anywhere in the class                  |
| Response For a Class       | CK 1994                       | `\|methods ∪ method-names invoked from those methods\|`                |
| Class Length               | Beck 1996; Fowler 1999; Lippert & Roock 2006 | total source lines spanned by the class declaration. "Large class" code smell (Beck / Fowler); threshold side via the "Rule of 30" (Lippert & Roock) |

LCOM4 and RFC use **name-based AST matching** scoped to the class declaration itself. LCOM4 only puts methods declared on the class into the graph (mixin-applied / inherited / extension methods are invisible); RFC's invoked-methods set comes from `MethodInvocation` and `InstanceCreationExpression` nodes only (extension tear-offs, callable-object `obj()`, and `super.x` are not counted). Both metrics intentionally under-report rather than over-report; file an issue with the snippet if you hit a misleading number.

### Library / file level (Martin 1994)

| Metric                                  | Notes                                                                   |
| --------------------------------------- | ----------------------------------------------------------------------- |
| Efferent Coupling (Ce)                  | distinct project-internal + `package:` dependencies (excludes `dart:*`) |
| Afferent Coupling (Ca)                  | incoming internal-import edges                                          |
| Instability (I)                         | `Ce / (Ca + Ce)`                                                        |
| Abstractness (A) **off**                | abstract-class + mixin / total class-like declarations. Off by default — Martin's framing assumes "package = release unit", and Dart's 1-file-1-library granularity makes the per-file value brittle |
| Distance from Main Sequence (D) **off** | `\|A + I − 1\|`. Off by default for the same reason as `abstractness` |

## AI integration

`--reporter ai` is the primary integration point. Output is a token-efficient YAML-ish bundle starting with `# dartrics ai-report v1`. The reporter knobs compose into a tight refactor loop:

- **Auto-explain** (default on; `--no-auto-explain` to opt out) auto-attaches the rationale + refactorHints + references for every metric that produced at least one violation. To pre-load the full catalogue (e.g. when an agent needs every metric's intent up front), pipe `dartrics rules --reporter ai` separately.
- **Stable violation `id`** — every violation carries a 16-hex-char `id = sha256("<file>|<scope>|<metric>")` so AI loops can correlate runs ("`a3f1c4e9…` showed up again ⇒ my fix didn't take"). Surfaces in the JSON / AI / md reporters and as `partialFingerprints.dartrics/v1` in SARIF. `dartrics explain <id>` reverse-looks up the full context from a saved JSON report.
- **`--limit <n>`** caps violations + unused entries shown by the AI / md reporters after the priority sort. Token-budget control for context-bounded agents; truncated entries are summarised in a `truncated:` block (AI) or `_+ N more_` line (md).
- **`--coverage <path>`** (auto-detects `coverage/lcov.info`) attaches per-scope line and branch coverage to every emitted violation. The reporter sorts by a priority key — low-coverage / high-severity entries land first, `complexityJustified` ones at the bottom.
- **`complexityJustified: true`** flags CC / Cognitive violations whose scope has branch coverage `≥ 0.8` (or line `≥ 0.95` when `BRDA:` records are absent). Two sibling fields surface the engine's decision: `complexityJustifiedBy` (`branch` or `line`) and `complexityJustifiedThreshold` (the literal cutoff). Intent: *earned complexity* — exhaustively-tested complex code is probably complex on purpose.
- **`--snapshot <mode>`** writes a per-file `sha256` after each run and emits only records for files whose hash changed on the next invocation. Git-independent, so it works for AI loops, pre-commit hooks, and non-git VCS (`jj`, `sapling`). `cache` (default) lands at `.dart_tool/dartrics/snapshot.json`; `baseline` at `dartrics-snapshot.json` for CI-shared baselines.
- **`--since <git-ref>`** filters output to declarations whose owning `.dart` file changed between `<ref>` and `HEAD`. Renames surface as the new path; untracked files are ignored. When `--since` and snapshot are both active, the git ref wins for filtering. Cross-file analysis stays accurate — only the *emitted* records are filtered.
- **`--strict-dismiss`** ignores every dismissal (comment + YAML) — useful in CI / final review when the operator wants the raw triage list. Combine with `--fatal-warnings` for a clean CI gate.

### Deliberate dismissal

Suppress a specific violation when a refactor would actually hide intent. Dismissals are a triaged-but-still-visible bucket: violations stay in the report, but `dismissed: true` (with the carried `reason`) tells AI loops to leave them alone. Two channels, both opt-in via `analysis_options.yaml`:

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
    warnStale: true             # surface dismissals that no longer match
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

Hits flow through the validator. Reasons that fall short of `minReasonLength` keep the violation **live** and stamp it with `dismissalRejected: <why>` (plus a stderr WARNING) so the agent can amend the entry. YAML always beats a colliding comment with the same key.

**Stale-entry detection**: when `warnStale: true` (the default), dismissals that never matched a live violation in the analyzed file set are surfaced as a stderr WARNING and as a `staleDismissals:` block on the AI / JSON reports. Entries whose file wasn't analyzed this run (filtered out by `--since` or snapshot) are not flagged as stale.

### Regression check

After the agent applies a fix:

```bash
dartrics regression --before HEAD~1 --after HEAD --reporter ai
```

The diff is per-scope, per-metric, classified as `improved` / `regressed` / `unchanged` / `added` / `removed` according to each metric's `MetricPolarity`. A built-in heuristic (`tinyHelpersAdded ≥ 3 AND slocDelta > 4·helpers AND ccReduction < 2·helpers`) flags refactors that look cosmetic — AI splitting one method into a swarm of one-line helpers without actually reducing branching — so the user notices.

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
    response-for-class: false          # disable a default-on metric

  unused:
    entry-points: ["main", "@pragma:vm:entry-point", "test"]
    exclude-exported: true
    ignore-annotations:
      - "visibleForTesting"
      - "protected"
      - "JsonSerializable"

  snapshot:
    mode: baseline           # cache | baseline | none

  exclude:
    - "lib/generated/**"
```

The `dartrics:` section is read by both the CLI and the analyzer plugin. The leading `# yaml-language-server` directive turns on autocomplete + typo detection in editors with [yaml-language-server](https://github.com/redhat-developer/yaml-language-server) integration.

### Code-gen keep-alive annotations

Every popular Dart codegen package's keep-alive annotation is honoured by the unused detector out of the box (freezed, json_serializable, dart_mappable, go_router_builder, auto_route, riverpod, injectable, hive / hive_ce, drift, test_reflective_loader), so source classes that depend on a yet-to-be-generated `.g.dart` / `.freezed.dart` / `.config.dart` partner aren't flagged as unused on a fresh checkout. The full annotation list lives in `dartrics rules` and in [`lib/src/unused/keep_alive_presets.dart`](lib/src/unused/keep_alive_presets.dart). Lookup is by **simple name only** (`@Freezed()` matches the simple name `Freezed`); for in-house codegen, list annotations under `dartrics: { unused: { ignore-annotations: [...] } }`.

## Public-API unused-code detection

Element-resolution-based BFS reachability over the analyzer's resolved element graph, rooted at `main`, declarations annotated with `@pragma('vm:entry-point')`, and (when `excludeExported` is enabled) every public symbol surfaced through a `lib/`-public file's `LibraryElement.exportNamespace`. Homonym methods on different classes are independent nodes, prefixed imports keep distinct identities, and SDK / dependency symbols never accidentally keep project declarations alive. Reports unused public functions, classes, mixins, extensions, typedefs, enums, top-level fields, and individual instance methods / fields / getters / setters / enum values.

To keep per-member reports actionable, the detector auto-roots:

- members marked `@override`,
- the Object dunder names (`toString`, `hashCode`, `==`, `noSuchMethod`, `runtimeType`),
- every public member of a class that carries a keep-alive annotation (`@JsonSerializable`, `@reflectiveTest`, every codegen preset).

Use `--filter <kinds>` (or `unused: { filter: [...] }`) to narrow the report to specific declaration kinds — `function`, `method`, `class`, `field`, `typedef`, `enum`, `extension`. `enum` targets individual enum constants; enum *type* declarations are filtered with `class`. Unknown names exit with a usage error so a typo doesn't silently drop every entry.

`dartrics unused --apply` deletes detected top-level declarations (functions / classes / typedefs / extensions) from disk in place — analogous to `dart fix --apply`. Refuses to run on a dirty git tree (override with `--force`), and skips files under `test/` / `integration_test/` by default (override with `--include-tests`). Instance methods, fields, and enum values are reported but not yet auto-deletable. After applying, run `dart fix --apply` to clean up newly unused imports.

Private (underscore-prefixed) names are intentionally skipped — `dart analyze`'s `dead_code` lint already covers them. Generated Dart files (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.config.dart`, `*.mocks.dart`, `*.pb*.dart`, `*.gen.dart`) are skipped during file collection.

## Analyzer plugin

`dartrics` ships its own analyzer plugin so the five lightweight function-level rules surface inline in `dart analyze` and the IDE.

```yaml
# analysis_options.yaml in your project
plugins:
  dartrics:
```

After saving, restart the analysis server (in VS Code: "Dart: Restart Analysis Server"). The plugin enables five rules by default:

| Rule                             | Default threshold |
| -------------------------------- | ----------------- |
| `dartrics_cyclomatic_complexity` | 10                |
| `dartrics_cognitive_complexity`  | 15                |
| `dartrics_maximum_nesting_level` | 4                 |
| `dartrics_number_of_parameters`  | 4                 |
| `dartrics_boolean_trap`          | 2                 |

Rule thresholds are read from the same `dartrics: { metrics: ... }` section the CLI uses; restart the analysis server after changes. Diagnostics surface at `info` severity — the current analyzer pipeline (`analysis_server_plugin 0.3.x` + `analyzer 13`) crashes the plugin isolate when a `LintCode` is constructed with anything other than `DiagnosticSeverity.INFO`, so the rules are pinned to INFO until that upstream constraint relaxes.

Heavier metrics (LCOM4, CBO, RFC, library coupling) and the public-API unused detector intentionally stay CLI-only because they require a project-wide index that an analysis-server plugin can't maintain efficiently per file.

## Flutter-aware mode

`dartrics: { flutter: true }` is the default. Its job is to recognise idiomatic Flutter constructor signatures so the threshold-style lenses don't churn on widget code that's actually fine.

| Target                           | Effect                                                                  |
| -------------------------------- | ----------------------------------------------------------------------- |
| Widget constructor               | `number-of-parameters` is skipped — a cushion for the rare positional-style widget constructor; idiomatic `MyWidget({super.key, ...})` already scores 0 from NOP's positional-only semantic |
| `Widget.build()`                 | **Measured normally.** Control-flow nesting only counts `if/for/while/switch/try/closure`, so a healthy declarative tree gives 0; method length is informative even on declarative code |
| Other methods on the same widget | Measured normally                                                       |

Detection is AST-only — a class counts as a widget when it directly extends `StatelessWidget`, `StatefulWidget`, `State`, `ConsumerWidget`, `ConsumerStatefulWidget`, `HookWidget`, or `HookConsumerWidget`. Non-Flutter packages are unaffected. Set `flutter: false` to force `number-of-parameters` on widget constructors too.

## Test-aware mode

`dartrics: { test: true }` is also the default. When the file under analysis sits under `test/` or `integration_test/` and its basename ends in `_test.dart`, the size-and-shape lenses step aside — arrange / act / assert blocks legitimately exceed `method-length` thresholds calibrated for production code, and nested `group(...)` / `setUp(...)` / `test(...)` scaffolding pushes `maximum-nesting-level` past 4 before any user logic begins.

| Scope             | Skipped on test files                                                |
| ----------------- | -------------------------------------------------------------------- |
| Function / method | `method-length`, `source-lines-of-code`, `maximum-nesting-level`     |
| Class             | `class-length`, `number-of-methods`                                  |

Cyclomatic complexity, cognitive complexity, number-of-parameters, boolean-trap, LCOM4 / CBO / RFC, and the library-level lenses still apply. Helpers in `test/` that don't end in `_test.dart` (e.g. `test/helpers.dart`) stay under the strict thresholds.

## AI report schema (v1)

```yaml
# dartrics ai-report v1
explain:                          # only present when auto-explain is on (default) and at least one metric fired
  - metric: cyclomatic-complexity
    rationale: |
      …one-paragraph rationale…
    refactorHints:
      - hint sentence
    references:
      - McCabe, T. J. (1976). A Complexity Measure. IEEE TSE.
violations:
  - file: lib/foo.dart
    id: a3f1c4e9b2d70218
    line: 42
    scope: Foo.bar
    metric: cyclomatic-complexity
    value: 12
    threshold: 10
    severity: warning
    coverage: 0.34                # only when --coverage is engaged
    branchCoverage: 0.20          # only when BRDA records exist
    complexityJustified: true     # only when set
    dismissed: true               # only when a dismissal accepted this violation
    snippet: |
      …7 lines centred on `line`…
unused:
  - file: lib/util.dart
    line: 88
    kind: function
    name: _legacyFormatter
```

Stable contract:

- `# dartrics ai-report v1` header is present on every emission.
- The snippet block is a YAML literal (`|`) of up to 7 lines (`line ± 3`).
- Field names are stable within a header version; new fields may be added.
- Breaking changes (renames, removals, semantic shifts) trigger a new header (`# dartrics ai-report v2`).

The JSON reporter emits the same logical model plus an `analyzedFiles` list (`{ path, sha256 }`) that backs the snapshot diff. `analyzedFiles` is JSON-only; the markdown / ai / sarif / console reporters omit it.

### JSON Schema files

Machine-checkable schemas live under [`schemas/`](schemas/):

- [`dartrics-report.schema.json`](schemas/dartrics-report.schema.json) — JSON reporter output.
- [`dartrics-dismissals.schema.json`](schemas/dartrics-dismissals.schema.json) — the `dartrics-dismissals.yaml` sidecar. Drop a `# yaml-language-server: $schema=…` directive at the top to get IDE autocomplete + validation.
- [`dartrics-config.schema.json`](schemas/dartrics-config.schema.json) — the `dartrics:` block of `analysis_options.yaml`.

All three schemas are draft-2020-12. Field additions are non-breaking; renames trigger a major version bump (`1` → `2` for the dismissals sidecar, `1.0` → `2.0` for the JSON report `version`).

## Output formats

- **console** — human-friendly summary line + per-violation lines.
- **json** — stable schema for `jq` pipelines and SARIF transformation.
- **md** — Markdown for PR comments and issue bodies, finalised through `package:dapper`'s `formatMarkdown`.
- **ai** — token-efficient YAML-ish report (see schema above).
- **sarif** — SARIF 2.1.0 envelope ingestible by GitHub Code Scanning / GitLab. `tool.driver.rules` is populated for every metric that fired — `fullDescription` carries the rationale, `help.markdown` carries the refactor hints + references, `helpUri` deep-links back to the README anchor.

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

`lib/dartrics.dart` is intentionally tight — it exposes only the function-level metric calculators so a custom CI bot or editor extension can compute one metric on a parsed `CompilationUnit` without spinning up the full engine.

| What you get | Names |
| --- | --- |
| Function-level metric calculators | `CyclomaticComplexity`, `CognitiveComplexity`, `MaxNestingLevel`, `NumberOfParameters`, `BooleanTrap`, `MethodLength`, `SourceLinesOfCode`, `HalsteadCounts` / `HalsteadVolume` |
| Calculator interface | `FunctionMetric`, `FunctionMetricInput`, `MetricPolarity` |
| Version string | `dartricsVersion` |

Anything not in this table is CLI-only and unsupported as a Dart import; reach for `dartrics analyze --reporter json` instead. `example/main.dart` shows a 30-line standalone embedding against `CyclomaticComplexity`.

## Limitations

- **The analyzer plugin covers only the five function-level rules** (CC, Cognitive, Max nesting, Number of parameters, Boolean-trap). LCOM4 / CBO / RFC / library coupling and the unused detector are CLI-only because they need a project-wide index that the analyzer-plugin API can't maintain efficiently per-file.
- **Built-in metric set is not exhaustive.** DIT / NOC / Halstead Difficulty / Halstead Effort / Maintainability Index are intentionally absent. Halstead Volume ships off-by-default. Bring your own opt-in for niche signals.
- **Not a fit if** you need per-line metric thresholds in the IDE for the full metric suite, you don't engage with the dismiss channel at all (a pure-fail-fast linter is a better fit), or you're on Dart < 3.10 / analyzer < 13.

## Development

```bash
dart pub get
dart format lib test example
dart analyze lib test example   # `dart analyze` (no path) loads the plugin isolate and may flake
dart test
dart pub run coverage:test_with_coverage  # 100% line coverage is required
```

See [`AGENTS.md`](AGENTS.md) for the contributor / AI-agent workflow notes.

### Bundled Claude Code skill

`.claude/skills/dart-cli-app-best-practices/` is a verbatim copy of the [`dart-cli-app-best-practices`](https://github.com/kevmoo/dash_skills) skill from [kevmoo/dash_skills](https://github.com/kevmoo/dash_skills) (Apache-2.0). It informs the CLI entrypoint conventions used in `bin/` and `lib/src/entry_point.dart` — keep it in sync upstream when refactoring.

## License

MIT for dartrics itself; the bundled skill in `.claude/skills/` is Apache-2.0 (see its `SKILL.md` frontmatter).
