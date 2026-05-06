# Changelog

## 0.1.0

First public release. The CLI, the analyzer plugin, and the embeddable Dart API ship from a single package.

### Metrics

- **Function / method**: cyclomatic complexity (McCabe 1976), cognitive complexity (Sonar 2018), maximum nesting level, number of parameters, boolean-trap (McConnell *Code Complete* 2004; Bloch *Effective Java* item 36 — count of `bool`-typed parameters, warning ≥ 2), source lines of code, method length. Halstead V/D/E (Halstead 1977) and the maintainability index (Oman 1992) ship off-by-default — opt in with `dartrics: { metrics: { <id>: { enabled: true } } }`.
- **Class**: number of methods, weighted methods per class (CK 1994), LCOM4 (Hitz & Montazeri 1995, connected-component variant), CBO and RFC (CK 1994), class length. CK's DIT and NOC are intentionally not provided — Dart's mixin / composition-over-inheritance culture keeps inheritance chains shallow, so they rarely produce signal.
- **Library / file**: efferent / afferent coupling, instability, abstractness, distance from main sequence (Martin 1994).
- Each metric exposes `rationale` (one-paragraph explanation anchored to the original paper), `refactorHints` (concrete moves), and `polarity` (`down` / `up` / `neutral`) so AI loops know which direction is "healthier" for the regression diff.

### Subcommands

- `dartrics analyze` runs every metric and the public-API unused detector over the analysis root.
- `dartrics unused` runs only the public-API reachability detector (fast path).
- `dartrics report <input.json>` re-emits a previously saved JSON report in a different format.
- `dartrics rules` catalogues every metric with its rationale + refactor hints in `--reporter ai|md|json|console`.
- `dartrics regression [--before <ref>] [--after <ref>]` compares metrics between two git states (default: `HEAD~1` vs the working tree). Uses git worktrees for the historical side. Diff entries are classified as `improved` / `regressed` / `unchanged` / `added` / `removed` per `MetricPolarity`. A built-in cosmetic-split heuristic flags refactors that look like AI just shuffled complexity into one-line helpers without actually reducing it.
- `dartrics manual` prints the AI-facing operator's manual to stdout. The content is a mirror of [`doc/manual.md`](doc/manual.md) embedded as a const string in the executable, so it travels with `dart pub global activate dartrics` and is reachable from any agent loop without a separate doc download. A parity test enforces byte-equality with the markdown source so the two cannot drift.

### AI integration (`--reporter ai`)

- Token-efficient YAML-ish output starting with `# dartrics ai-report v1`. The header is contractual; field renames or removals trigger a new header (`v2`).
- **Auto-explain** (default on; `--no-auto-explain` opts out) attaches each fired metric's rationale + refactor hints to the report's `explain:` block — AI loops no longer need to know to pass `--explain <id>` for every threshold they care about.
- `--explain <metric-id>` (repeatable) is still honoured and **unions** with auto-explain; explicit ids stay first in the order so authored prompts remain deterministic.
- **Stable violation `id`** — every violation carries a 16-hex-char `sha256("<file>|<scope>|<metric>")` so AI loops can correlate runs ("`a3f1c4e9…` showed up again ⇒ my fix didn't take"). Surfaces in the JSON / AI / md reporters and as `partialFingerprints.dartrics/v1` in SARIF. Exported as `computeViolationId(file, scope, metricId)` for embedders.
- **`--limit <n>`** caps the violations + unused entries shown by the AI / md reporters after the priority sort. AI report records the dropped count in a `truncated:` block; md report appends `_+ N more violation(s) hidden by --limit_`. JSON / SARIF / console stay unlimited.
- `--coverage <path>` (auto-detects `coverage/lcov.info`) attaches per-scope line and branch coverage to every emitted violation. The reporter sorts by a priority key that puts low-coverage entries first and `complexityJustified` ones last so token budget lands on the most actionable items.
- `complexityJustified: true` flags CC / Cognitive violations whose scope has branch coverage ≥ 0.8 (or line ≥ 0.95 when no `BRDA:` records are present) — *earned complexity* AI loops should leave alone.
- **Deliberate dismissal** lets agents triage a specific `(file, scope, metric)` triple via `// dartrics:dismiss <metric> reason="…"` comments or a `dartrics-dismissals.yaml` sidecar. Both channels are opt-in through `dartrics: { dismissals: … }` in `analysis_options.yaml`. Validated entries decorate the violation with `dismissed: true` + carried `reason` / `by` / `at`; entries that fail `requireReason` / `minReasonLength` / `requireAuthor` / `requireTimestamp` keep the violation **live** and stamp it with `dismissalRejected: <why>` plus a stderr WARNING. `--strict-dismiss` ignores every dismissal for the run.
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
- Opt-in code-gen presets (`freezed`, `json_serializable`, `dart_mappable`, `go_router_builder`, `auto_route`) seed the keep-alive annotation list so source classes aren't flagged on a fresh checkout before `dart run build_runner build`.
- Generated Dart files (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.config.dart`, `*.mocks.dart`, `*.pb*.dart`, `*.gen.dart`) are skipped during file collection. Override with `AnalyzerRunner(includeGenerated: true)` if you really want them.
- Private (underscore-prefixed) names are intentionally skipped — `dart analyze`'s `dead_code` lint already covers them.

### Analyzer plugin

- `plugins: dartrics` in `analysis_options.yaml` enables four function-level rules (`dartrics_cyclomatic_complexity` / `_cognitive_complexity` / `_maximum_nesting_level` / `_number_of_parameters`) inline in `dart analyze` and the IDE.
- Rule thresholds are configurable through the same `dartrics:` section the CLI uses (long form `{ warning: <n>, error: <n> }` or bare-integer short form). The plugin honours `flutter: true` for the same skip rules as the CLI.
- Heavier metrics (LCOM4, CBO, RFC, library coupling) and the unused detector stay CLI-only — they need a project-wide index that an analysis-server plugin can't maintain efficiently per file.
- Diagnostics surface at INFO severity due to an upstream `analysis_server_plugin` 0.3.x constraint (non-INFO `LintCode` crashes the plugin isolate).

### Flutter-aware mode

- `dartrics: { flutter: true }` is the default. Skips `maximum-nesting-level` and `method-length` on `Widget.build()` and `number-of-parameters` on widget constructors — five-to-seven-deep `Container` trees and key/callback parameter lists are normal in idiomatic Flutter and shouldn't churn AI refactor loops. Non-Flutter packages are unaffected because no class extends a known widget superclass. Set `flutter: false` to force the lenses on widget code anyway.
- Detection is AST-only across `StatelessWidget`, `StatefulWidget`, `State`, `ConsumerWidget`, `ConsumerStatefulWidget`, `HookWidget`, `HookConsumerWidget`. Cyclomatic / cognitive complexity, SLOC, and class- / library-level metrics still apply, including on widget helpers.

### Test-aware mode

- `dartrics: { test: true }` is the default. When the file under analysis sits under `test/` or `integration_test/` and its basename ends in `_test.dart` (the conventional `dart test` discovery marker), `method-length` / `source-lines-of-code` / `maximum-nesting-level` are skipped at function level and `class-length` / `number-of-methods` are skipped at class level. AAA blocks and nested `group`/`setUp`/`test` scaffolding don't dominate the diagnostic stream that way. Helpers under `test/` whose basename does not end in `_test.dart` (e.g. `test/helpers.dart`) stay under the strict thresholds. Set `test: false` to apply the production-grade thresholds to test files too.
- Cyclomatic complexity, cognitive complexity, number-of-parameters, boolean-trap, LCOM4 / CBO / RFC, and the library-level lenses still apply — branchy or tangled tests are still hard to read.

### CLI surface

- Common options: `--config`, `--reporter`, `--output`, `--root`, `--since`, `--explain`, `--snapshot`, `--coverage`, `--strict-dismiss`, `--concurrency`, `--limit`, `--auto-explain` / `--no-auto-explain`, `--fatal-warnings`, `--fatal-style`, `-v`.
- `dartrics --version` prints the build's version. The same string is exported as `dartricsVersion` from `package:dartrics/dartrics.dart`.
- Exit codes are sysexits-aligned: 0 success, 1 violations (with `--fatal-warnings`), 64 usage, 65 data, 70 internal, 78 config.

### Embedding

- `lib/dartrics.dart` exposes the metric calculator classes (`CyclomaticComplexity`, `CognitiveComplexity`, `Lcom4`, …), the report shapes (`AnalysisReport`, `MetricRecord`, `MetricViolation`, `MetricChange`, `RegressionReport`, …), the metadata enums (`MetricPolarity`, `ChangeDirection`, `Severity`, `ScopeKind`, `DismissalSource`), and the supporting types and helpers (`CoverageIndex`, `FileCoverage`, `AnalyzedFile`, `ExplainEntry`, `Dismissal`, `DismissalConfig`, `computeViolationId`, `dartricsVersion`).
- `example/main.dart` shows a 30-line standalone embedding.

### Performance

- File resolution in `AnalyzerRunner.resolveAll` now uses `package:pool` to run up to `--concurrency` resolves in flight at once. Default mirrors the host CPU count (clamped to 16). Output ordering remains alphabetical so reports stay deterministic across runs. The win on smaller trees (≈50 files) is ≈10 % wall-time; larger codebases get more.

### Tooling

- `.github/workflows/ci.yaml` runs format, analyze, test, and `coverage:test_with_coverage` on Ubuntu and macOS for every push and PR.
- 100% line coverage on `lib/` is treated as a correctness signal — uncovered lines are read as evidence of dead code, not as a coverage gap.
