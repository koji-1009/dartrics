# Changelog

## 0.3.0

### Breaking changes

- **`--explain <metric-id>` removed from `dartrics analyze` and `dartrics unused`.** Auto-explain has been the default since 0.1.0 and inlines every fired metric's rationale + refactorHints + references already; the only remaining role of `--explain` was injecting a metric's rationale even when it didn't fire, which is better served by piping `dartrics rules --reporter ai` into the agent's context separately. For post-hoc lookup of a single violation, use `dartrics explain <id> --input report.json`.
- **`MetricPolarity.up` removed from the enum.** No built-in metric ever used it (the only `up` metric was the maintainability index, dropped in 0.1.0 as a derivation of CC + V + LOC). Custom embedder metrics that registered with `MetricPolarity.up` will fail to compile against 0.3.0; treat the metric as `neutral` (regression diff surfaces deltas without classifying them as improvement / regression). The up-polarity arms of `regression_diff.dart::_directionByPolarity` and `doctor_command.dart::checkThresholdOrdering` are removed.
- **`dartrics: { unused: { presets: [...] } }` removed.** The field has been a no-op since 0.1.0 (every codegen preset is always honoured as a keep-alive root, regardless of the list). The loader, the `Config.UnusedConfig.presets` field, the `expandPresets` helper, the doctor's "unknown unused preset" validator, and the corresponding entry in `dartrics-config.schema.json` are all removed. Existing `analysis_options.yaml` files that still list `presets:` will fail validation against the schema; remove the key. For in-house codegen, list annotations under `unused: { ignore-annotations: [...] }`.

### `dartrics ai-loop` subcommand

- `dartrics ai-loop` prints the four-station AI-loop walkthrough (setup → propose → apply → verify) to stdout. The body is embedded as a const string mirrored byte-for-byte from [`doc/ai-loop.md`](doc/ai-loop.md), so it travels with `dart pub global activate dartrics` — agents that have just installed dartrics can read the loop contract from the binary itself without a separate doc download. Pairs with the existing `dartrics manual` (the lens reference) so the manual + walkthrough are both reachable from inside an agent loop. A parity test enforces byte-equality so the two cannot drift.

### Structured `references` field on every metric

- `FunctionMetric` / `ClassMetric` / `LibraryMetric` gain `List<String> get references` (default `const []` so custom embedder metrics are unaffected). Built-in metrics now expose their primary source as a structured list — McCabe 1976 for cyclomatic complexity, Campbell / SonarSource 2018 for cognitive complexity, NIST SP 500-235 for maximum nesting level, Beck 1996 for method length, Halstead 1977, Boehm 1981 for SLOC, Fowler 1999 for number-of-parameters, McConnell 2004 + Bloch 2008 for boolean-trap, Chidamber & Kemerer 1994 for WMC / CBO / RFC, Hitz & Montazeri 1995 for LCOM4, Martin 1994 for the library-coupling family. Empty by default for metrics that don't trace to a published source (max-nesting was already cited; Dart-3-idiom lenses and the simpler size lenses stay empty).
- Surfaces in `dartrics rules` (ai / md / console / json), `dartrics explain <id>` (ai + json), the AI / md reporters' explain blocks, and SARIF `help.text` / `help.markdown` next to the rationale + refactor hints. Each reporter gates the references block on isNotEmpty; uncited metrics produce byte-identical output to 0.2.x. JSON omits the field when empty so existing schemas / consumers see no shape change.
- `RuleDescription` and `ExplainEntry` carry the field through to every reporter; embedders consuming `dartrics analyze --reporter json` will see new `references: [...]` arrays on rule descriptors when a metric is cited.

### Manual drift gate

- `test/cli/manual_command_test.dart` now asserts both directions against the live metric catalogue: every id from `collectRuleDescriptions()` appears as a back-ticked token in `## The lens battery` of `doc/manual.md`, and every back-ticked id at the start of a lens-table row resolves back to a registered metric. Region-scoped to that section so back-ticked tokens elsewhere (`if`, `package:`, `MethodInvocation`, …) aren't mistaken for metric ids. The byte-equality test alone caught prose drift but not metric-vs-doc drift.

### Documentation cleanup

- README rewritten and trimmed (545 → 429 lines, –21 %). 'In five lines' / 'Why dartrics' / 'Recommendation' folded into a single 'What it does' section; 'Honest limitations' + 'Who should not adopt yet' merged into 'Limitations' (dropped three bullets that duplicated information in the AI-integration knob list or in `doc/ai-loop.md`); '--since (diff mode)' inlined into the AI-integration knob list; the AI-report YAML sample shortened (the full sample lives in `doc/ai-loop.md`); the per-package code-gen keep-alive annotation table replaced with a single paragraph pointing at `dartrics rules` and `lib/src/unused/keep_alive_presets.dart`; Embedding section trimmed.
- AI-leftover prose swept from tracked artifacts: `tmp/` reference removed from `test/analyzer_runner_test.dart`; pre-0.1.0 / matches-0.1.0 wording removed from CLI help and rationale strings (CHANGELOG records 0.1.0 as the first public release); AI session-memory references ("Round 4's stable id", "Round 2-4 added", "Round 5") removed from explain_command, report_command_test, unused_apply_cli_test, coverage_cli_test; "in 0.1.0 / as of 0.1.0 / since 0.1.0" version stamps removed from ~25 sites across `lib/`, `test/`, `doc/manual.md`, and the byte-mirrored `manual_text.dart`; test-justification dartdoc ("Exposed for tests", "Extracted so tests can …") trimmed from public dartdoc on entry_point, regression_diff, doctor_command, git_diff, unused_detector, lint_options, explain_command, analysis_report. None of these change runtime behaviour.

## 0.2.2

### Bugfixes

- `maximum-nesting-level` no longer counts named-argument closures (Widget builders, event handlers) as a nesting level. `ListView.builder(itemBuilder: (...) {})` and `ElevatedButton(onPressed: () {})` were reporting `1` even when no `if` / `for` was involved — directly contradicting the contract that `widget_tree_depth.dart` and `flutter_aware.dart` both document ("a healthy Widget tree produces a nesting score of 0"). Closures still increment when passed positionally (`xs.forEach((x) {})`, `xs.fold(0, (a, x) => …)`) — those are higher-order calls, not declarative configuration. Inner `if` / `for` inside a named-argument closure still counts at the right depth.
- The summary table now surfaces snapshot mode and the diff filter so the cache-mode default doesn't render as a regression. Without these rows the second run with no source changes filtered every violation through `_filterUnused` and rendered as `unused declarations: 0` indistinguishable from "really nothing fired". Adds `snapshot mode: cache` / `files changed: 0 of 3 (no new findings)` to the md summary, a top-level `snapshot:` block to the AI reporter, a `[snapshot cache: 0 of 3 changed]` tail tag to the console line, and `snapshotMode` + `changedFileCount` fields at the JSON report root. Field additions only — `# dartrics ai-report v1` and the JSON `1.0` header stay valid.

## 0.2.1

### Bugfix

- `.pubignore`'s `coverage/` pattern (no leading slash) matched at any depth, so the published `0.1.0` and `0.2.0` archives shipped without `lib/src/coverage/coverage_loader.dart` and `lib/src/coverage/lcov_reader.dart` even though both are imported by `lib/src/cli/analyze_command.dart` and `lib/src/metrics/metric_engine.dart`. Anyone who installed from pub.dev hit unresolved-import errors. The pattern is now `/coverage/`, matching `.gitignore`. No source-code changes; reinstall to recover a working package.

## 0.2.0

### Public-API unused-code detection — element-resolution mode

- The CLI's `dartrics analyze` and `dartrics unused` paths now run the public-API reachability analysis over the analyzer's resolved element graph instead of the simple-name reference graph that shipped in 0.1.0. The detector keys reachability on canonical `Element.id`s of project-local declarations, so homonym methods on different classes are independent nodes (calling `Foo.bar()` no longer accidentally keeps `Baz.bar()` alive), prefixed imports keep distinct identities, and SDK / dependency symbols never pull through to project declarations they happen to share a name with.
- Reachability is now tracked at member granularity. The detector reports unused instance methods, fields, getters, setters, and enum values in addition to the top-level kinds — same `UnusedKind` enum as before, just with the per-class entries populated. Existing 0.1.0 callers will see new entries with `kind: method | field | enumValue` in the unused list once a class is reachable; pass `--filter class,function,extension,typedef` (or set `unused: { filter: [...] }` in `analysis_options.yaml`) to restore the top-level-only shape.
- New `--filter <kinds>` CLI flag (and matching `unused: { filter: [...] }` YAML key) narrows the report to a subset of declaration kinds. Accepted names: `function`, `method`, `class`, `field`, `typedef`, `enum`, `extension`. `enum` targets individual enum constants; enum *types* are filtered with `class`. Comma-separate or repeat the flag (`--filter method,field`). Unknown names exit `ExitCode.usage` with a did-you-mean style error.
- Auto-rooting rules added to keep the per-member reports clean:
  - Members marked `@override` are rooted (covers interface / superclass overrides without us walking the supertype hierarchy).
  - Object dunder names — `toString`, `hashCode`, `==`, `noSuchMethod`, `runtimeType` — are rooted; the language runtime calls them, not user source.
  - When a class carries any keep-alive annotation (`@JsonSerializable`, `@reflectiveTest`, every codegen preset, …) every public member of that class is rooted too — these annotations signal generator / reflective consumers that read members by name.
- New `reflectiveTest` keep-alive preset added to `keep_alive_presets.dart` so `@reflectiveTest` classes from `package:test_reflective_loader` keep their `test_*` members alive.
- `LibraryElement.exportNamespace` now drives the `excludeExported` root set, so re-exported `lib/src/` types (and every public method / field / getter / setter on them) survive without relying on textual `show` matching.
- The parse-only `UnusedDetector.detect` entry point stays as a fallback for tests / embedders that don't want a real `AnalysisContextCollection`. `dartrics analyze` / `dartrics unused` route through the new `UnusedDetector.detectResolved` path automatically — no caller changes required.

## 0.1.0

First public release. The CLI, the analyzer plugin, and the embeddable Dart API ship from a single package.

### Design philosophy

dartrics is built on the wager that the AI coding loop changes which software metrics are practically usable. The academic catalogue — McCabe 1976, CK 1994, LCOM4 1995, Martin 1994, Cognitive Complexity 2018 — has long been underused in everyday workflows because each of *calculating* the number, *interpreting* it, and *acting on it* was individually expensive for a human reviewer. An AI loop absorbs all three: the CLI computes in milliseconds, `--auto-explain` delivers the rationale, and the agent acts on it.

Each metric is treated as a single **lens** — one dimension of "hard to read." Lenses are independent and stackable: an agent can iterate through dozens in a session, refactor under each, then re-evaluate. dartrics surfaces what each lens reads; the accept / refactor / dismiss decision is first-class and stays in the loop.

The metric set, the thresholds, and the Flutter / test relaxations below are calibrated for Dart. The lens framing and the AI-loop contract are language-agnostic.

### Metrics

- **Function / method**: cyclomatic complexity (McCabe 1976), cognitive complexity (Sonar 2018), maximum nesting level (control-flow only — `if`/`for`/`while`/`switch`/`try`/closure; widget-literal chains do not count), number of parameters (Fowler 1999 — *positional-only*; named parameters are weight-zero because the call site `foo(a: …, b: …)` carries each argument's name on the spot, dissolving the position-counting load Fowler's lens targets — same rule as `boolean-trap`), boolean-trap (McConnell *Code Complete* 2004; Bloch *Effective Java* item 36 — count of `bool`-typed parameters, warning ≥ 2), source lines of code. Halstead Volume (Halstead 1977), method length, and `widget-tree-depth` (deepest chain of nested constructor calls — Flutter community ~5–7 threshold) ship off-by-default — opt in with `dartrics: { metrics: { <id>: { enabled: true } } }`. Method length is default-off because its correlation with SLOC in production code is high enough (often > 0.95) that emitting both is redundant noise — opt in when you specifically want the "screen real estate" reading (counts blank lines + comments) on top of SLOC's "actual code volume" reading. Halstead Difficulty / Effort and the Maintainability Index (Oman 1992) were dropped because they are pure derivations of the underlying token counts and `CC + V + LOC` respectively.
- **Class**: number of methods, weighted methods per class (CK 1994), LCOM4 (Hitz & Montazeri 1995, connected-component variant), CBO and RFC (CK 1994), class length. CK's DIT and NOC are intentionally not provided — Dart's mixin / composition-over-inheritance culture keeps inheritance chains shallow, so they rarely produce signal.
- **Library / file**: efferent / afferent coupling, instability (Martin 1994). Abstractness and distance from main sequence ship default-off because Martin's framing assumes "package = release unit" and Dart's 1-file-1-library granularity makes the per-file values brittle (a single `abstract class Foo` in its own file scores A=1.0 without saying anything about the design layer it participates in). Opt-in until the directory-level aggregation lands.
- Each metric exposes `rationale` (one-paragraph explanation anchored to the original paper), `refactorHints` (concrete moves), and `polarity` (`down` / `up` / `neutral`) so AI loops know which direction is "healthier" for the regression diff.

### Subcommands

- `dartrics analyze` runs every metric and the public-API unused detector over the analysis root.
- `dartrics unused` runs only the public-API reachability detector (fast path).
- `dartrics report <input.json>` re-emits a previously saved JSON report in a different format.
- `dartrics rules` catalogues every metric with its rationale + refactor hints in `--reporter ai|md|json|console`.
- `dartrics regression [--before <ref>] [--after <ref>]` compares metrics between two git states (default: `HEAD~1` vs the working tree). Uses git worktrees for the historical side. Diff entries are classified as `improved` / `regressed` / `unchanged` / `added` / `removed` per `MetricPolarity`. A built-in cosmetic-split heuristic flags refactors that look like AI just shuffled complexity into one-line helpers without actually reducing it.
- `dartrics manual` prints the AI-facing operator's manual to stdout. The content is a mirror of [`doc/manual.md`](doc/manual.md) embedded as a const string in the executable, so it travels with `dart pub global activate dartrics` and is reachable from any agent loop without a separate doc download. A parity test enforces byte-equality with the markdown source so the two cannot drift.
- `dartrics doctor` validates the `dartrics:` block in `analysis_options.yaml`. Surfaces unknown metric ids (with did-you-mean suggestions via Levenshtein distance ≤ 2), unknown unused presets, and threshold orderings inconsistent with each metric's polarity (e.g. `cyclomatic-complexity: { warning: 20, error: 10 }` is flagged because lower-is-better metrics need `error ≥ warning`). Read-only — never edits the config. Exit codes: 0 clean, 1 warnings, 78 invalid YAML / `ConfigException`.
- `dartrics explain <id>` reverse-looks-up a violation by its stable 16-hex-char id and prints the matching entry plus the metric's rationale + refactor hints. Reads a JSON report (the format produced by `dartrics analyze --reporter json`) from stdin or `--input <path>`. AI agents that see the same id reappear across runs ("my fix didn't take") can retrieve full context for that id without re-reading the entire report.

### AI integration (`--reporter ai`)

- Token-efficient YAML-ish output starting with `# dartrics ai-report v1`. The header is contractual; field renames or removals trigger a new header (`v2`).
- **Auto-explain** (default on; `--no-auto-explain` opts out) attaches each fired metric's rationale + refactor hints to the report's `explain:` block — AI loops no longer need to know to pass `--explain <id>` for every threshold they care about.
- `--explain <metric-id>` (repeatable) is still honoured and **unions** with auto-explain; explicit ids stay first in the order so authored prompts remain deterministic.
- **Stable violation `id`** — every violation carries a 16-hex-char `sha256("<file>|<scope>|<metric>")` so AI loops can correlate runs ("`a3f1c4e9…` showed up again ⇒ my fix didn't take"). Surfaces in the JSON / AI / md reporters and as `partialFingerprints.dartrics/v1` in SARIF. Exported as `computeViolationId(file, scope, metricId)` for embedders.
- **`--limit <n>`** caps the violations + unused entries shown by the AI / md reporters after the priority sort. AI report records the dropped count in a `truncated:` block; md report appends `_+ N more violation(s) hidden by --limit_`. JSON / SARIF / console stay unlimited.
- `--coverage <path>` (auto-detects `coverage/lcov.info`) attaches per-scope line and branch coverage to every emitted violation. The reporter sorts by a priority key that puts low-coverage entries first and `complexityJustified` ones last so token budget lands on the most actionable items.
- `complexityJustified: true` flags CC / Cognitive violations whose scope has branch coverage ≥ 0.8 (or line ≥ 0.95 when no `BRDA:` records are present) — *earned complexity* AI loops should leave alone. Two sibling fields surface the engine's decision: `complexityJustifiedBy` (`branch` or `line`, whichever rule won) and `complexityJustifiedThreshold` (the literal cutoff that rule used). Reporters pass the trio through verbatim — JSON, AI / YAML, MD, SARIF, `dartrics explain`.
- **Deliberate dismissal** lets agents triage a specific `(file, scope, metric)` triple via `// dartrics:dismiss <metric> reason="…"` comments or a `dartrics-dismissals.yaml` sidecar. Both channels are opt-in through `dartrics: { dismissals: … }` in `analysis_options.yaml`. Validated entries decorate the violation with `dismissed: true` + carried `reason` / `by` / `at`; entries that fail `requireReason` / `minReasonLength` / `requireAuthor` / `requireTimestamp` keep the violation **live** and stamp it with `dismissalRejected: <why>` plus a stderr WARNING. `--strict-dismiss` ignores every dismissal for the run. **Stale-entry detection** (default-on, `warnStale: true`): dismissals that never matched a live violation in the analyzed file set surface as a stderr WARNING and as a `staleDismissals:` block on the AI / JSON reports, so AI loops can prune dead entries when scopes are renamed / deleted or metrics drop below threshold. Skipped for files filtered out by `--since` / snapshot.
- `--since <git-ref>` filters output to declarations whose owning `.dart` file changed between `<ref>` and `HEAD`. Cross-file analysis still resolves the full project so LCOM4 / library coupling / public-API reachability stay accurate; only the *emitted* records are filtered.
- End-to-end loop walkthrough — setup → propose → apply → verify, with sample prompts and troubleshooting — lives in [`doc/ai-loop.md`](doc/ai-loop.md).
- AI-facing operator's manual — each metric framed as a lens on "hard to read" with the accept / refactor / dismiss decision step made first-class — lives in [`doc/manual.md`](doc/manual.md).

### Reporters

- `console` — human-readable summary line + per-violation entries.
- `json` — stable schema for `jq` pipelines and SARIF transformation; carries `analyzedFiles` (sha256 list) when snapshot mode is engaged.
- `md` — Markdown for PR comments and issue bodies, formatted via `package:dapper.formatMarkdown`.
- `ai` — described above.
- `sarif` 2.1.0 — GitHub Code Scanning / GitLab ingestion. `tool.driver.rules` is populated for every metric that fired in the run, carrying the rationale in `fullDescription`, the refactor hints in `help.markdown`, and `helpUri` deep-linking back to the README anchor — so the platform surfaces the full lens explanation inline next to each result instead of an opaque rule id.

### Public-API unused-code detection

- Periphery-style BFS reachability over a name-based reference graph rooted at `main`, declarations annotated with `@pragma('vm:entry-point')`, and (when `excludeExported` is enabled) `lib/` exports outside `lib/src/`. Follows `export ... show ...` clauses so re-exported `lib/src/` symbols stay reachable. Reports unused public functions, classes, mixins, extensions, typedefs, enums, and top-level fields.
- Code-gen keep-alive annotations are **always on**: `freezed`, `json_serializable`, `dart_mappable`, `go_router_builder`, `auto_route`, `riverpod_generator`, `injectable`, `hive`, `drift`. Listing `presets:` in `analysis_options.yaml` is no longer required (the field is still parsed for backward compatibility with older configs but no longer narrows the keep-alive set). The simple-name match means an annotation from a package you don't use simply never fires, so there's no per-project cost to leaving every preset on.
- Generated Dart files (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.config.dart`, `*.mocks.dart`, `*.pb*.dart`, `*.gen.dart`) are skipped during file collection. Override with `AnalyzerRunner(includeGenerated: true)` if you really want them.
- Private (underscore-prefixed) names are intentionally skipped — `dart analyze`'s `dead_code` lint already covers them.
- `dartrics unused --apply` deletes detected top-level declarations from disk (analogous to `dart fix --apply`). Refuses to run on a dirty git tree without `--force`. Files under `test/` or `integration_test/` are excluded by default; pass `--include-tests` to include them. Supports function / class / typedef / extension deletion; method / field / enum-value deletion is reported as `unsupported` because the range computation needs containing-declaration awareness that is deferred. Imports left unused after deletion can be cleaned up with `dart fix --apply`.

### Analyzer plugin

- `plugins: dartrics` in `analysis_options.yaml` enables five function-level rules (`dartrics_cyclomatic_complexity` / `_cognitive_complexity` / `_maximum_nesting_level` / `_number_of_parameters` / `_boolean_trap`) inline in `dart analyze` and the IDE.
- Rule thresholds are configurable through the same `dartrics:` section the CLI uses (long form `{ warning: <n>, error: <n> }` or bare-integer short form). The plugin honours `flutter: true` for the same skip rules as the CLI.
- Heavier metrics (LCOM4, CBO, RFC, library coupling) and the unused detector stay CLI-only — they need a project-wide index that an analysis-server plugin can't maintain efficiently per file.
- Diagnostics surface at INFO severity due to an upstream `analysis_server_plugin` 0.3.x constraint (non-INFO `LintCode` crashes the plugin isolate).

### Flutter-aware mode

- `dartrics: { flutter: true }` is the default. Its only effect in 0.1.0 is to **skip `number-of-parameters` on widget constructors**, which stays as a cushion for the rare positional-style widget constructor — in practice an idiomatic `MyWidget({super.key, required this.title, ...})` already scores 0 from NOP's positional-only semantic, so the skip is a no-op for typical Flutter code. `Widget.build()` is measured normally — `maximum-nesting-level` only counts control-flow constructs (`if`/`for`/`while`/`switch`/`try`/closure), so a healthy declarative tree produces a depth of 0 without any special-casing, and `method-length` is informative even on declarative trees.
- Visual depth from chained Widget literals (`Container(child: Container(...))`) is the responsibility of the `widget-tree-depth` lens — opt-in for Flutter authors that want this signal, default warning 7 (matching Flutter community practice of ~5–7 before extracting a sub-widget).
- Detection is AST-only across `StatelessWidget`, `StatefulWidget`, `State`, `ConsumerWidget`, `ConsumerStatefulWidget`, `HookWidget`, `HookConsumerWidget`. Set `flutter: false` to force `number-of-parameters` on widget constructors too.

### Test-aware mode

- `dartrics: { test: true }` is the default. When the file under analysis sits under `test/` or `integration_test/` and its basename ends in `_test.dart` (the conventional `dart test` discovery marker), `method-length` / `source-lines-of-code` / `maximum-nesting-level` are skipped at function level and `class-length` / `number-of-methods` are skipped at class level. AAA blocks and nested `group`/`setUp`/`test` scaffolding don't dominate the diagnostic stream that way. Helpers under `test/` whose basename does not end in `_test.dart` (e.g. `test/helpers.dart`) stay under the strict thresholds. Set `test: false` to apply the production-grade thresholds to test files too.
- Cyclomatic complexity, cognitive complexity, number-of-parameters, boolean-trap, LCOM4 / CBO / RFC, and the library-level lenses still apply — branchy or tangled tests are still hard to read.

### CLI surface

- Common options: `--config`, `--reporter`, `--output`, `--root`, `--since`, `--explain`, `--snapshot`, `--coverage`, `--strict-dismiss`, `--concurrency`, `--limit`, `--auto-explain` / `--no-auto-explain`, `--fatal-warnings`, `--fatal-style`, `-v`.
- `dartrics --version` prints the build's version. The same string is exported as `dartricsVersion` from `package:dartrics/dartrics.dart`.
- Exit codes are sysexits-aligned: 0 success, 1 violations (with `--fatal-warnings`), 64 usage, 65 data, 70 internal, 78 config.

### Embedding

- `lib/dartrics.dart` is a deliberately tight Dart API: the eight function-level metric calculators (`CyclomaticComplexity`, `CognitiveComplexity`, `MaxNestingLevel`, `NumberOfParameters`, `BooleanTrap`, `MethodLength`, `SourceLinesOfCode`, `HalsteadVolume`), the calculator interface (`FunctionMetric`, `FunctionMetricInput`, `MetricPolarity`), and `dartricsVersion`. That's it. Report assembly, regression diff, coverage attachment, dismissal validation, snapshot persistence, the unused detector, and class- / library-level metrics are CLI-only — the JSON reporter is the supported on-wire format for those scopes. Keeping the public Dart surface small means internal evolution doesn't break consumers we don't yet have; if a Dart-level handle is missing for a real use case, please file an issue rather than reaching into `package:dartrics/src/`.
- `example/main.dart` shows a 30-line standalone embedding.

### Performance

- File resolution in `AnalyzerRunner.resolveAll` uses `package:pool` to run up to `--concurrency` resolves in flight at once. Default mirrors the host CPU count (clamped to 16). Output ordering remains alphabetical so reports stay deterministic across runs. The win on smaller trees (≈50 files) is ≈10 % wall-time; larger codebases get more.

### Tooling

- `.github/workflows/analyze.yaml` runs format / analyze / test on Ubuntu for every push and PR, then uploads `coverage:test_with_coverage` output to Codecov where per-PR coverage gating happens.
- 100% line coverage on `lib/` is treated as a correctness signal — uncovered lines are read as evidence of dead code, not as a coverage gap.
