# Changelog

## 0.6.0

A calibration release. Two metrics drop because their academic anchoring did not survive a re-audit against original sources; four citations are corrected; the Dart-specific deviations from cited definitions consolidate into a single `doc/calibration.md` audit page; the README is restructured around the three things a "back of the box" surface should answer (philosophy / what it does / what metrics) with everything else moved to the dedicated docs.

### Breaking changes

- **`maximum-nesting-level` removed.** A re-audit found the cited authority — "NIST SP 500-235 §4 reports a strong correlation between deep nesting and bug density" — to be incorrect: §4 of that document is "Simplified Complexity Calculation", not nesting research. With the misciting removed, the metric had no peer-reviewed source establishing a defect-correlated threshold for raw nesting depth — only PMD / Checkstyle / SonarLint convention. Dropped rather than shipped on tooling-convention backing. The `MaxNestingLevel` calculator, the `MaximumNestingLevelRule` analyzer-plugin rule, the `dartrics_maximum_nesting_level` lint id, the `maximum-nesting-level` config key, and the `MaxNestingLevel` public-API export are all removed. CI configs that pinned a `maximum-nesting-level: { warning: <n> }` block must drop the entry — the schema's `propertyNames.enum` no longer accepts the id and `dartrics doctor` will flag it.
- **`boolean-trap` removed.** A re-audit found the McConnell *Code Complete* and Bloch *Effective Java* item 36 attributions wrong: the term "boolean trap" was coined by Ariya Hidayat (2011) in a community blog post, and Bloch's item 36 in the 2nd edition is "Consistently use the Override annotation" — unrelated. With the academic backing reduced to a community blog post, and the `dart-lang/linter` rule `avoid_positional_boolean_parameters` already covering the same ground with a stricter binary threshold (it flags any positional bool, not just two or more), the count-based dartrics framing was both weaker than the official lint and unanchored. Recommendation: enable `avoid_positional_boolean_parameters` in `analysis_options.yaml`. The `BooleanTrap` calculator, the `BooleanTrapRule` analyzer-plugin rule, the `dartrics_boolean_trap` lint id, the `boolean-trap` config key, and the `BooleanTrap` public-API export are all removed.

### Citation corrections

- `cognitive-complexity` — Campbell / SonarSource white paper is **2017** (with revisions in 2018, 2021, 2023), not 2018. Title kept; year corrected. The rationale now flags the source as "industry white paper, not peer-reviewed" and notes that predictive value beyond McCabe's CC has not been independently validated.
- `halstead-volume` — Alfadel et al. is **2017**, **9th IEEE-GCC Conference and Exhibition (GCCCE), pp. 1–9**, not 2018 / "IEEE Conference on Computer and Information Technology". The "~0.9 mean correlation" specific figure is softened to "strong positive linear correlation" because the underlying paper's text could not be confirmed for the precise numeric claim during the re-audit.
- `lcom4` — Hitz & Montazeri (1995) introduced the connected-components cohesion variant; the "LCOM4" label is a later community convention (Henderson-Sellers' LCOM1–LCOM5 numbering). The rationale now reflects that distinction.
- `martin 1994` — full bibliographic citation expanded in the library-coupling family's `references` from the bare "Martin, R. C. (1994)" to "Self-published essay, August 14, 1994 (rev. June 20, 1995); cross-posted to comp.object and comp.lang.c++. Content later folded into Martin (2002), *Agile Software Development: Principles, Patterns, and Practices*, Ch. 28, Prentice Hall." The C++ Report attribution that some downstream sources use is incorrect — Martin became Editor-in-Chief of C++ Report in 1996, after the essay was already in circulation.

### `doc/calibration.md` — new audit trail

A single page documenting the relationship between dartrics' implementation and its cited sources: selection principles, counting-rule deviations from the literal source definitions (sealed-aware CC, positional-only NOP, declared-methods-only LCOM4), and off-by-default rationales. Threshold *numbers* (CC warn 10, CBO warn 14, …) follow the cited sources unchanged; the page enumerates only the cases where dartrics deviates from those sources, and why. README's "Provided metrics" preamble and `doc/manual.md`'s "The lens battery" preamble link out to it instead of duplicating the rationale inline. Lenses not in the current catalogue are not enumerated — that history lives in this CHANGELOG.

### README restructured around "back of the box" content

- The README is roughly 58 % shorter (437 → 184 lines). Three priorities stay on the page: the lens-battery + AI-loop philosophy, what dartrics does at a glance, and the metric inventory with thresholds. Everything else moves to the dedicated docs that ship inside the binary (`dartrics manual`, `dartrics ai-loop`) or to the JSON Schema files that already define the wire format.
- Sections collapsed to a 1–2 line pointer: the long flag listing under "Subcommands" (replaced by a per-command `--help` reference + link to `doc/manual.md`), "AI integration" (token-budget knobs, `--coverage`, `complexityJustified`, `--snapshot`, `--since`, `--strict-dismiss`), "Generating the coverage data", "Deliberate dismissal" (comment + YAML examples), "Regression check", "Code-gen keep-alive annotations", "Public-API unused-code detection", "Flutter-aware mode", "Test-aware mode", "AI report schema (v1)", "JSON Schema files", and "Exit codes". All of that content already lives in `doc/manual.md`, `doc/ai-loop.md`, or the `schemas/` files; the README now links there instead of mirroring it.
- A new "Documentation" section enumerates the four reading entry points (`dartrics manual`, `dartrics ai-loop`, `doc/calibration.md`, `schemas/`) so first-time readers immediately see where the operator-level detail lives.
- The Configuration section keeps only the minimum config example (yaml-language-server directive + a couple of metric thresholds + exclude); per-key reference moves to the schema file and `dartrics manual`.

### Analyzer plugin

- `plugins: dartrics` now enables three function-level rules — `dartrics_cyclomatic_complexity` / `_cognitive_complexity` / `_number_of_parameters`. The previous `_maximum_nesting_level` and `_boolean_trap` rules are gone with their underlying metrics.

## 0.5.1

A maintenance release. No metric, threshold, exit-code, or wire-format change — `# dartrics ai-report v1`, every JSON / SARIF schema, and the public Dart API (`FunctionMetric`, `FunctionMetricInput`, `MetricPolarity`, `dartricsVersion`) stay byte-compatible with 0.5.0. The release modernises internals against the Dart 3.10 idiom now that the SDK floor (`environment: sdk: ^3.10.0`) has settled, plus two CI / docs hygiene items.

### Internal: Dart 3 switch and pattern adoption

- The function-level metric helpers in `lib/src/metrics/metric.dart` (`_bodyOf` / `_parametersOf` / `_scopeNameOf` / `_enclosingClassName`) move from `if (x is FunctionDeclaration) ... else if (x is MethodDeclaration) ...` chains to `switch` expressions with type patterns and destructuring. `regression_diff.dart::_directionOrder` becomes a 1-statement `switch` expression over `ChangeDirection`. `metric_engine.dart::_buildViolation` consumes the sealed `DismissalCheck` via an exhaustive `switch`; the previous `final rejected = check as DismissalRejected` cast is gone, and adding a third sealed subclass is now a compile-time error rather than a runtime cast failure.
- The string-format dispatchers (`pickReporter`, `resolveSnapshotConfig`, `_modeFromString`, the void-returning `RegressionReporter.report` / `RulesReporter.report`) collapse into single `switch` expressions or no-fallthrough `switch` statements. The `'none' | 'off'` synonym uses a single OR pattern.
- `library_metric._countClasses`, `lcom4.ingest`, `wmc.compute`, `rfc.compute` walk the analyzer's sealed `ClassMember` hierarchy with destructured patterns. The sealed walk in `lcom4.ingest` declares its no-op fallback case explicitly instead of relying on `if-else` skip-through.

### Internal: `CallableDecl` sealed wrapper

- A new private `sealed class CallableDecl` in `lib/src/metrics/metric.dart` concentrates the analyzer-`Declaration`-to-callable type fan-out into a single `CallableDecl.from(Declaration)` factory — a 3-line `if`-chain plus a trailing `as ConstructorDeclaration` cast — and lets the rest of the metric layer dispatch through three subclasses that override `body` / `parameters` / `scopeName` directly. The previous `switch`-expression helpers shipped a `_ => throw ArgumentError(...)` wildcard arm in each, since analyzer's `Declaration` is open and the type system can't prove exhaustiveness over the three subtypes the engine actually passes in. With the wrapper, exhaustiveness arms are no longer needed, and analyzer version updates that introduce a fourth `Declaration` subtype only need a single factory amendment instead of four wildcard arms. `FunctionMetricInput.body` / `parameters` / `scopeName` keep their same shape — `late final` fields delegating through the wrapper — so embedders see no API change.

### Internal: dot-shorthand syntax

- Dart 3.10's dot-shorthand is now used throughout `lib/src/` wherever the target type is inferable from context — return types on the same line (`MetricPolarity get polarity => .down;`), `switch` subjects (`switch (config.mode) { .none => ... }`), enum-to-enum equality (`kind != .function`), and named-arg positions where the parameter type names the enum (`SnapshotConfig(mode: .cache)`, `ScopeRef(kind: .library)`, `MetricChange(polarity: polarity[id] ?? .neutral)`). No semantic change; the same tokens reach the metric layer. A handful of sites stay in long form: ternaries whose target type is inferred from a sibling branch, `Severity.values.byName(...)` / `ScopeKind.values.byName(...)` static-collection access, and one default-value site where the type comes from a YAML coercion that names both branches.

### Tooling: dartrics self-application CI gate

- A new GitHub Actions job runs `dart run bin/dartrics.dart analyze --root . --snapshot none --reporter ai` on every push and PR and fails the build if dartrics' own source produces any warning-level violation. Codifies the dogfood loop principle — the lens battery only stays honest if the canonical idiomatic-Dart codebase the project itself ships clears it. Runs after the `analyze` (static) job so `dart analyze` lints catch first, then dartrics gates on its own metric battery. Uses `dart run` against the in-tree source rather than installing the package so the gate works against unreleased states.

### Docs: coverage data prerequisite

- The README's `--coverage` documentation, the in-binary `dartrics manual`, and the `dartrics ai-loop` walkthrough now spell out how to generate `coverage/lcov.info` (the file the auto-detection looks for) — `dart pub global activate coverage` plus the matching `dart run` / `flutter test --coverage` command. Previously the docs assumed users already had the lcov file in place and only described the auto-detection step.

## 0.5.0

A pruning release. Five pieces of dead-or-deferred CLI / model surface come off — flags that advertised behavior they did not honor, a subcommand that overlapped with auto-explain, an enum value no lens emits — plus one payload addition (`MetricChange.id`) on the regression side.

### Breaking changes — CLI

- **`dartrics explain <id>` subcommand removed.** Auto-explain has been default-on since 0.1.0 and inlines every fired metric's rationale + refactorHints + references next to the violation, so the AI loop already has the "why" without a second tool call. The subcommand's only remaining role was post-hoc lookup against a saved JSON report — but a saved report already carries the same `explain:` block, and looking the entry up directly in the JSON is one `Map<id, violation>` build away with zero process-spawn overhead. Going through the CLI added a Dart VM cold-start (50–300 ms AOT, ~1–3 s under `dart run`) per lookup, which is wasteful inside an AI loop that may dereference dozens of ids. Drop any tooling that shells out to `dartrics explain`; read the JSON report's `violations:` and `explain:` blocks directly instead.
- **`--no-auto-explain` flag removed.** Auto-explain is now unconditional. The opt-out existed for "lean reports without rationale", but the entire reason an AI loop pipes dartrics into a model is to consume the rationale alongside the violation; the flag was a holdover from before auto-explain was the default. The `explain:` block still only appears when at least one metric fired (clean runs stay clean). Token-budget control belongs to `--limit <n>` instead, which trims violations rather than stripping their justification.
- **`--fatal-style` flag removed from every subcommand.** The flag exited non-zero on `Severity.info`, but no built-in lens has ever emitted that severity — `MetricEngine._classifyThreshold` only returns `Severity.error` / `Severity.warning`, and unused / SARIF paths don't synthesize info either. The flag was a YAGNI hold-out for a hypothetical future info-tier and was indistinguishable in `--help` from a working option. CI configs that pass `--fatal-style` will now fail with `Could not find an option named "--fatal-style"`; remove the flag. `--fatal-warnings` is unaffected.
- **Per-subcommand option scoping.** `addCommonOptions` was a single dump of 13 flags onto every subcommand even though `report` ignored 9 of them and `unused` ignored 3. Same UX disease as `--fatal-style`: `--help` advertised behavior the command did not honor. The helper splits into `addIoOptions` (`--reporter`, `--output`, `--limit`, `--verbose`), `addAnalysisOptions` (`--config`, `--root`, `--since`, `--snapshot`, `--concurrency`, `--fatal-warnings`), and `addMetricsReadingOptions` (`--coverage`, `--strict-dismiss`). `analyze` opts into all three, `unused` opts into the first two, `report` opts into IO only. The `CommonOptions` class likewise splits into `IoOptions` / `AnalysisOptions` / `MetricsReadingOptions`. CI scripts that passed analysis-time flags to `dartrics report` (e.g. `dartrics report r.json --root .`) will now fail with `Could not find an option named "--root"`; drop them — they were no-ops.

### Breaking changes — model

- **`Severity.info` removed from the enum.** No built-in lens ever emitted it and no user-visible feature consumed it; the only reference was a SARIF reporter case-arm mapping it to `note`. Removed in lockstep with `--fatal-style`. The SARIF reporter's `_level` switch is now an exhaustive switch expression on `{warning, error}`. The summary block in the markdown reporter likewise drops its `info` row. Custom embedder metrics that synthesized `Severity.info` will fail to compile against 0.5.0; treat as `warning`. The decoder in `report_command.dart` will throw `ArgumentError` on a saved JSON containing `level: info` — saved reports older than 0.5.0 that emit `info` will need to have those entries rewritten or filtered out before re-emission.

### `dartrics regression` carries the violation id

- Each `MetricChange` now exposes a stable `id` field and emits it in the AI / JSON output. The id is the same `sha256("<file>|<scope>|<metric>")[..16]` that `MetricViolation.id` uses, so a regressed row in `dartrics regression --reporter ai` is one direct lookup away from the matching violation in the analyze report (or its SARIF `partialFingerprints.dartrics/v1`). The id is computed from fields the row already carries — emitted unconditionally, including for sub-threshold deltas where no violation was recorded — so AI loops can correlate even sub-threshold drift across runs without rebuilding the triple by hand. The regression diff itself still keys on `(file, scope.kind, scope.name)` at the scope granularity (a record holds many metric values; an id would force per-metric matching and lose the kind disambiguation), so this is a payload addition, not a matching-key change.

### Internal: auto-explain lookup moves into MetricEngine

- The auto-explain pipeline used to round-trip through `buildExplanations(List<String>)` in `rules_command.dart`, a helper that defended against duplicate / blank / unknown metric ids. Every one of those branches was unreachable in practice: violation `metricId`s come from the same `defaultFunctionMetrics` / `defaultClassMetrics` / `defaultLibraryMetrics` lists that `findRuleDescription` walks, and the upstream id collector already deduplicated. The helper and its test were keeping the dead branches alive without any production caller able to reach them. Embedders did not have a path to inject unknown ids either: `MetricEngine` is not exported from `lib/dartrics.dart` (`FunctionMetric` is, but the engine isn't), so custom calculators cannot be registered through the public API.
- Auto-explain now lives where the calculator set lives. `MetricEngine.firedExplanations(List<MetricRecord>) → List<ExplainEntry>` iterates the engine's own `functionMetrics` / `classMetrics` / `libraryMetrics`, filters by the set of metric ids that fired in the records, and emits one `ExplainEntry` per fired metric. The lookup is *structural* over the calculator set rather than a nullable Map indirection, so the previous `findRuleDescription(...)!` bang at the call site disappears: the relationship "fired metric ⇒ has a rationale" is the type itself, not an unchecked invariant. Output order is calculator-declaration order (function, class, library) instead of first-violation order; AI consumers index by `metricId` rather than position, so this is informational. `analyze_command.dart` drops `_firedExplanations` and the now-unneeded `rules_command` import; `buildExplanations` and its test are gone with it.

## 0.4.0

### Breaking changes

- **Three Dart-shape metrics removed: `widget-tree-depth`, `null-aware-chain-depth`, `async-chain-depth`.** All three were tool-originated lenses with no academic anchor and no Effective Dart consensus to point to — out of step with the catalogue's "every metric is anchored to its primary source" rule. `widget-tree-depth` was lint-shaped (deepest `InstanceCreationExpression` chain) and is better expressed as a `custom_lint` rule than as a metric. `null-aware-chain-depth` and `async-chain-depth` measure call-shape patterns the language already gives clean rewrites for (`?.` short-circuit + early-return for the former; `Future.wait` / hoisting for the latter), so the metric was re-deriving guidance the language semantics already imply. All three were off-by-default, so the impact is limited to projects that opted into them — drop the entries from `dartrics: { metrics: { ... } }`. The schema's `propertyNames.enum` no longer accepts the three ids.
- **`FunctionMetric.references` and `ClassMetric.references` are now abstract.** With the three function-level lenses removed and citations added for `number-of-methods` and `class-length`, every remaining built-in metric overrides `references` in both abstract classes, so the empty-default getters became dead code. Embedders implementing custom `FunctionMetric`s or `ClassMetric`s now need to declare `List<String> get references => const [];` explicitly when there is no primary citation — same shape `LibraryMetric` has always required. The three abstract bases are now consistent.

### Class-metric citations

- `number-of-methods` now cites **Lorenz & Kidd (1994)** and **Chidamber & Kemerer (1994)**. Lorenz & Kidd's *Object-Oriented Software Metrics: A Practical Guide* (Prentice Hall, ISBN 0-13-179292-X) includes the per-class method count in their 11-metric OO-size suite, catalogued as "Average number of methods per class"; CK's WMC reduces to NOM when each method is weighted at 1.
- `class-length` now cites **Beck (1996)**, **Fowler (1999)**, and **Lippert & Roock (2006)**. Beck's *Smalltalk Best Practice Patterns* and Fowler's *Refactoring* frame the underlying "large class" code smell; Lippert & Roock's *Refactoring in Large Software Projects* (Wiley, ISBN 0-470-85892-3) adds the threshold side via the "Rule of 30" — a class averaging more than 30 methods (~900 LOC) is highly likely to need decomposition.
- README's class-level table and the manual's class-lens section (mirrored in `doc/manual.md` + `lib/src/cli/manual_text.dart`) replace the placeholder `—` with the new citations.

### README "Designed for the AI loop"

- The differentiation pitch is promoted to a dedicated `### Designed for the AI loop` subsection inside "What it does", expanded into a 5-item feature list (auto-explain by default, stable IDs with reverse lookup, coverage-aware reading, output stability, docs in the binary). The previous "Who it's for" bullet is dropped — every other paragraph already pitches AI agents and the humans driving them as the audience. The "signals, not gates" framing remains in the lead paragraph where it belongs as operating philosophy rather than as a feature.

### "Provided metrics" preamble

- The off-by-default justification now names both **Halstead Volume** (strongly correlated with both cyclomatic complexity and SLOC: ~0.9 mean correlation per Alfadel et al. 2018; redundant rather than orthogonal signal) and **Method Length** (= SLOC + blank lines + comment-only lines by definition, so SLOC alone carries the same signal plus a known offset) with their distinct rationales. Pre-0.4.0 the preamble named only Halstead Volume; the three Dart-shape lenses being off too made the parenthetical read as a partial example, but with those gone the off-by-default group is just the two metrics, both nameable. The earlier wording asserted Halstead's "predictive value over cyclomatic complexity has not held up empirically" and Method Length is "highly correlated with SLOC in production code"; the first claim was wrong-direction (Alfadel et al. find correlation, not inferiority), the second was an uncited observational estimate. Both are reframed as overlap with simpler signals: Halstead via correlation evidence, Method Length via the definitional identity.

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
