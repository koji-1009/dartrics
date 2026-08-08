# Changelog

## 1.3.1

`dartrics --version` and the exported `dartricsVersion` constant identified 1.3.0 as `1.2.0`. No metric, threshold, exit-code, or schema change.

* `dartricsVersion` matches `pubspec.yaml` again. Tooling that gates on the reported version string — not on the resolved pub constraint — read 1.3.0 as 1.2.0 and needs no change beyond upgrading.

## 1.3.0

Cyclomatic and cognitive complexity cover modern Dart 3 syntax, closures become their own records, and unused-detector / `regression` false positives are fixed. Scores and findings can change on unchanged code; dismissals left without a live finding surface in `staleDismissals:`. Report schema `1.2` → `1.3`, additive; tracks analyzer 14.

* `dartrics doctor` warns on unknown keys under `dartrics:`, with a did-you-mean hint.
* `dartrics regression`: library scopes match between `--before` and `--after`, the `--before` revision resolves `package:` imports (no more phantom diffs on identical code), and leftover `dartrics_worktree_*` registrations are reclaimed at startup.
* Unused detector: operators called only via compound assignment (`acc += v`) are no longer flagged; `dartrics analyze` runs the unused pass over generated files, matching `dartrics unused` (metric records and counts still exclude them); under `exclude-exported` (the default), public members an exported class inherits from project-internal supertypes count as reachable.
* Cyclomatic complexity counts switch-expression arms (the bare `_ =>` arm, like `default:`, is not counted), `??`, and `??=`; the exhaustive-switch discount now covers enums. See `doc/calibration.md`.
* Cognitive complexity scores if-case `when` guards.
* Closures are measured as separate function records: scope kind `closure`, scope name `<enclosing scope>.closure#N` with `N` the source-order ordinal — inserting an earlier closure shifts later siblings, so ids and dismissals on closure scopes need re-anchoring.
* Report schema `1.2` → `1.3`: `ScopeRef.type` gains `closure`. Additive.
* Dependency floors raised: Dart SDK `^3.11.0`, `analyzer ^14.0.0`, `analysis_server_plugin ^0.3.19`, `analyzer_testing ^0.3.3` (dev).

## 1.2.0

Toolchain alignment release: tracks analyzer 13.1.0. No metric, threshold, exit-code, or schema change.

* Dependency floors raised: `analyzer ^13.1.0`, `analysis_server_plugin ^0.3.16`, `analyzer_testing ^0.3.0` (dev). The deprecated `ExtensionTypeDeclaration.primaryConstructor` AST getter is replaced with its successor `namePart`; behaviour is unchanged.

## 1.1.0

An AI-loop fidelity release: the `ai` report announces per-section totals, `--since` narrows to the scopes the diff touched, and cognitive complexity stops taxing declarative test registration. Report schema `1.1` → `1.2`, additive. No threshold, exit-code, or wire-format-breaking change.

* **`--reporter ai` emits a `counts:` block** (violations / unused / staleDismissals / signals) ahead of the sections. All four sections share the `  - file:` entry shape, so agents that grepped to count findings over-counted; totals now read from `counts:` plus `truncated:` for dropped tails. `--limit` is documented as what it always was — a per-section cap, not a global one.
* **`--since <ref>` filters violations to the scopes the diff touched.** The filter was file-granular: an untouched function re-surfaced whenever a sibling in the same file changed. Violations now intersect `git diff -U0` hunk ranges with the scope span; `unused` / `signals` stay file-granular because they are call-graph-relational — a change elsewhere in the file can legitimately flip them on an untouched declaration. Pure renames (100% similarity, no hunks) no longer surface.
* **Cognitive complexity applies a test-DSL discount.** On `*_test.dart` files under `test/` / `integration_test/`, closures passed as invocation arguments (`group()` / `test()` registration callbacks) no longer accrue to the enclosing function — declarative test mains were firing purely on the closure-nesting tax. The function's own control flow and named helpers stay scored. Gate with `dartrics: { test: false }`; applies to both the CLI engine and the analyzer-plugin rule. **Stale-dismissal note:** `// dartrics:dismiss cognitive-complexity` comments that suppressed the closure-nesting tax on test mains may now be reported as stale — remove them.
* Report schema `1.1` → `1.2`: `ScopeRef` gains an optional `endLine` (last line of the declaration, inclusive) — the span `--since` intersects. Additive; pre-1.2 reports re-emit through `dartrics report` unchanged.

## 1.0.0

First stable release. The metric battery, the `--reporter ai` wire format (`# dartrics ai-report v1`), the JSON and SARIF schemas, and the embeddable Dart API (`FunctionMetric` family + `dartricsVersion`) commit to semver — non-breaking until 2.0.0. No metric, threshold, exit-code, or wire-format change from 0.8.0. The metric catalogue is `dartrics rules`; the operator reference is `doc/manual.md` and `dartrics manual`; the wire formats are in `schemas/`.

* One-time editorial pass over the 0.x CHANGELOG entries. Verbose originals remain at `pub.dev/packages/dartrics/versions/<version>` and in `git log`.

## 0.8.0

Correctness release. Several lenses, the coverage reader, the regression diff, and the report writers had edge-case defects; `dartrics unused --apply` is also narrowed to the deletions it can make safely. No metric default or schema change.

* **`dartrics unused --apply` now performs only whole-node deletions.** A variable that shares an `int x, y, z;` declaration with siblings, and enum constants, are reported as `unsupported` and left in place for you to remove — `--apply` no longer rebalances the surrounding commas (which could leave invalid Dart). dartrics surfaces those decisions rather than guessing at them; the unused detector still lists the declaration.
* **Cyclomatic complexity no longer folds a nested closure into the enclosing function.** A lambda's `if` / `&&` / `case` decision points were leaking into the value of the function that contained it; nested closures are measured separately, as documented.
* **lcov branch coverage keys on `(line, block, branch)`.** Two distinct branches that share a line and branch number across different blocks (e.g. an `&&` that lowers to two blocks) no longer collapse last-write-wins, so the branch-coverage fraction behind `complexityJustified` is correct.
* **`dartrics regression --root <sub-dir>` compares the matching sub-tree on both sides.** `git worktree add` checks out the whole repository, so the historical side previously analysed the entire repo and normalised paths against the repo root — every scope reported as added + removed. It is now scoped to the sub-directory.
* **Report output escapes special characters.** A free-text field such as a dismiss reason starting with `-` or `[` no longer breaks the re-parsed `ai` / `rules` YAML, and a `|` in a scope name (e.g. `operator |`) no longer splits the Markdown signals table.
* **A non-numeric metric threshold raises a config error.** A quoted or otherwise non-numeric value (`error: "15"`, which YAML reads as a string) was silently dropped, so a gate without a built-in default never fired; it is now reported instead of dropped or coerced.

## 0.7.3

Detection-fidelity and discoverability release driven by external agent feedback. No metric, threshold, or schema change.

* **Unused detector now follows operator-method calls through `IndexExpression`, `BinaryExpression`, and the operator element on `PrefixExpression` / `PostfixExpression`.** User-defined `operator []`, binary operators (including custom `+` / `==`), unary `-`, and the `+` reached via `c++` / `c--` were previously flagged as unused when their only caller was the textual operator form. `==` overrides were already kept alive by the `Object` dunder auto-root, but their `signals:` fan-in / fan-out (and `dartrics inspect ==` upstream walk) now reflect the actual call sites. **Stale-dismissal note:** projects with `// dartrics:dismiss unused` comments suppressing the prior false-positives on those operators may now see those dismissals reported as stale — remove them.
* **`dartrics ai-loop` repositioned as the operational entry point.** Its `--help` one-liner now reads "Operational playbook: commands, prompts, dismiss syntax (start here for AI agents)."; `dartrics --help` gains a footer pointing at it; `doc/manual.md` opens with a cross-ref banner; and the README "AI agents — start here" admonition, Quick start block, Subcommands table, and Documentation list all lead with `ai-loop` and reframe `manual` as the conceptual reference (lens design, decision tree, flag catalogue). Driven by an agent who skipped `ai-loop` because the prior blurb read as a recap of the manual.

## 0.7.2

AI-consumer ergonomics release driven by a real dartrics session report from another agent. No metric, threshold, or schema change.

* **`looksCosmetic` → `cosmeticSplitDetected`** in `dartrics regression`. The old name read as a verdict; the detector is a narrow opt-in signal (the cosmetic-split signature) parallel to `analyze`'s `signals:` block, not a refactor-quality verdict. All reporters now emit `# narrow heuristic, not a global verdict` alongside the boolean, and the manual reframes the block as a signal rather than a pass/fail.
* **Stray `// dartrics:dismiss` comments no longer silently no-op.** When `commentSource` is off (the default — the `dismissals:` block is not yet authored) and the run is not `--strict-dismiss`, `analyze` scans for dismiss-shaped comments and emits a stderr WARN naming the affected files and the opt-in needed.
* **Operational protocol step 5 documents `--snapshot none`.** The snapshot cache rewrites itself every run, so two consecutive `analyze` runs always report `changedFiles: 0`. The manual now flags this on the verify step.
* **README directs AI agents to `dartrics manual` first.** The subcommand was hidden behind `--help`; the README banner makes it the explicit entrypoint for AI consumers.
* **ACCEPT becomes a first-class decision** in the loop diagram and manual. Borderline values on healthy code are now explicitly "no edit, no `// dartrics:dismiss`, no punt — move to the next violation," distinct from dismiss (which is a tracked, recurring-reason commitment).

## 0.7.1

Documentation-only release. The 0.7.0 surface — `dartrics inspect`, the `signals:` reference block — shipped without matching updates to `dartrics manual` and `dartrics ai-loop`. 0.7.1 catches the in-binary walkthroughs up to the released CLI surface. No code, schema, or threshold change.

* `dartrics ai-loop` sample report now carries `signals:` and `snapshot:`; documents what the agent reads out of it and clarifies that `violations:` / `explain:` go absent on a clean run while `signals:` keeps emitting. New "The unused-detector loop" section covers the `read → inspect → --apply` flow.
* `dartrics manual` gains a "Signals — reference information, not verdicts" section, an inline `dartrics inspect` subsection, and an `inspect` entry in the operational protocol flag map.

## 0.7.0

A call-graph release. The element-resolved reachability pass already powering `dartrics unused` now also surfaces per-declaration fan-in / fan-out reference signals and backs a new `dartrics inspect <symbol>` subcommand. Signals carry no threshold and no severity — they are reference information, not violations.

* Report schema bumps from `1.0` to `1.1`. Three new top-level fields land in the JSON output: `signals`, `explanations` (previously AI / MD only), and `staleDismissals` (previously AI only). All additive; `additionalProperties: false` is now consistent with `toJson` again. See `schemas/dartrics-report.schema.json`.
* New `dartrics inspect <symbol> [--depth N] [--direction up|down|both]` subcommand. Walks upstream callers and / or downstream callees within `--depth` hops; emits JSON or the YAML-ish AI shape. Homonym methods on different classes stay disambiguated as separate matches.
* MD reporter gains `## Signals (reference)` and `## Stale Dismissals` sections. The AI reporter's `unused:` block is reframed in-output: entries may be leftover code OR unwired implementations — the framing comments instruct the loop to confirm against intent before acting.

## 0.6.6

A `dartrics unused` correctness fix. Detection now sees references that live inside machine-generated files. Output changes for any project whose source declarations are reached only from generated code (`.g.dart`, `.freezed.dart`, etc.). No CLI flag, exit code, schema, or threshold change.

* `dartrics unused` reachability now includes references from machine-generated files; previously edges like a `riverpod_generator` provider's reference back to its source function were missing and the source was reported unused. Snapshots and the analyzed-file count still track the handwritten subset only. `dartrics analyze`'s unused output retains the same defect. Surfaced by dogfooding on a multi-module `riverpod_generator` project.

## 0.6.5

A README narrative simplification. No metric, threshold, exit-code, or wire-format change.

* Drops the wager and lens paragraphs from `## What it does` (duplicated `doc/manual.md`'s `## The premise`); the `## Documentation` entry for `dartrics manual` now signposts the design premise.

## 0.6.4

A dead-code cleanup surfaced by dogfooding dartrics on its own source. No metric, threshold, exit-code, or wire-format change.

* `SourceLocation.toJson` removed — every serializer that holds a `SourceLocation` builds its own field set inline, so the method had no caller in `lib/`. Detected by running `dartrics analyze` on dartrics itself.

## 0.6.3

A `dartrics unused --apply` correctness fix plus two documentation additions. No metric, threshold, exit-code, or wire-format change.

* `unused --apply --filter field` now refuses fields whose name appears as a `this.<field>` initializing formal on the enclosing class's constructor; previous behaviour broke compilation. New `ApplyOutcome.coupledConstructorFormal` marks each refused entry.
* `unused --apply` no longer leaks the leading whitespace of a deleted declaration into the next line.
* `doc/manual.md` — "Punt" section now names the output channel (natural-language between AI and operator; no comment directive or YAML key); new `## Reporters — pick by audience` section.

## 0.6.2

A documentation-only patch on top of 0.6.1. No metric, threshold, exit-code, or wire-format change.

* Per-file Martin lenses (`efferent-coupling` / `afferent-coupling` / `instability`) reframed from `polarity: down` to `polarity: neutral` in docs to match the `LibraryMetric` default; rationale in `doc/calibration.md`'s new "Per-file Martin granularity" section.
* README metric tables gain a `Default warning` column in place of `Notes`; the library-level table tags `instability` as informational; `## Limitations` surfaces "Per-file Martin granularity".

## 0.6.1

A small documentation-correctness patch on top of 0.6.0. No metric, threshold, exit-code, or wire-format change.

* `unused --apply` summary message rewritten — the previous text claimed methods, fields, and enum values were "not yet auto-deletable" (stale since 0.5.x). Only "removing the last constant of an enum" remains an unsupported `ApplyOutcome.unsupportedKind` outcome.

## 0.6.0

A calibration release. Four metrics drop after a citation re-audit, four citations corrected, and the Dart-specific deviations from cited sources consolidate into `doc/calibration.md`.

### Breaking changes

* `maximum-nesting-level` removed — the cited NIST SP 500-235 §4 attribution was incorrect and no peer-reviewed alternative establishes a defect-correlated threshold. The calculator, plugin rule, lint id, config key, and public-API export are gone. Schema's `propertyNames.enum` no longer accepts the id.
* `boolean-trap` removed — the McConnell / Bloch attributions were wrong; `dart-lang/linter`'s `avoid_positional_boolean_parameters` already covers the ground with a stricter binary threshold.
* `abstractness` and `distance-from-main-sequence` removed — Martin's "package = release unit" framing has no equivalent in Dart's language model. Rationale in `doc/calibration.md`.

### Citation corrections

* `cognitive-complexity` — SonarSource 2017 (not 2018); rationale now flags the source as an industry white paper.
* `halstead-volume` — Alfadel et al. 2017, 9th IEEE-GCC Conference, not the previously-cited 2018 venue.
* `lcom4` — Hitz & Montazeri (1995) introduced the connected-components variant; the "LCOM4" label is a later community convention.
* `martin 1994` — full bibliographic citation; the C++ Report attribution that some sources use is incorrect.

### Other

* `doc/calibration.md` — new audit page for selection principles, counting-rule deviations, and off-by-default rationales.
* README trimmed by ~58 % (437 → 184 lines); content redistributed to `dartrics manual` / `dartrics ai-loop` / `schemas/`.

## 0.5.1

A maintenance release. No metric, threshold, exit-code, or wire-format change. Internals modernised against Dart 3.10 idiom, plus a self-application CI gate and a coverage-data docs fix.

* New CI job runs `dartrics analyze` on dartrics itself on every push/PR and fails on warning-level violations.
* Coverage-data docs in README / `dartrics manual` / `dartrics ai-loop` now spell out how to generate `coverage/lcov.info` (previously assumed users already had it).

## 0.5.0

A pruning release. Five pieces of dead-or-deferred CLI / model surface come off, plus one payload addition on the regression side.

### Breaking changes

* `dartrics explain <id>` subcommand removed — auto-explain has been default-on since 0.1.0; lookup against a saved JSON report is a direct `Map<id, violation>` build.
* `--no-auto-explain` flag removed — auto-explain unconditional. Token-budget control is `--limit <n>`.
* `--fatal-style` flag removed from every subcommand — `Severity.info` was never emitted by any built-in lens.
* Per-subcommand option scoping — `--root` and analysis-time flags no longer accepted by `dartrics report` (drop them from CI scripts).
* `Severity.info` removed from the public enum — embedder metrics that synthesised it will fail to compile; treat as `warning`.

### Other

* `MetricChange.id` field added — same `sha256("<file>|<scope>|<metric>")[..16]` as `MetricViolation.id`, emitted unconditionally so AI loops can correlate sub-threshold drift across runs.

## 0.4.0

### Breaking changes

* Three Dart-shape metrics removed: `widget-tree-depth`, `null-aware-chain-depth`, `async-chain-depth`. All three were tool-originated lenses without academic anchor; schema's `propertyNames.enum` no longer accepts the ids.
* `FunctionMetric.references` and `ClassMetric.references` are now abstract — embedders implementing custom metrics must declare `List<String> get references => const [];` explicitly when there is no primary citation.

### Other

* `number-of-methods` cites Lorenz & Kidd (1994) and CK (1994); `class-length` cites Beck (1996), Fowler (1999), and Lippert & Roock (2006).

## 0.3.0

### Breaking changes

* `--explain <metric-id>` removed from `dartrics analyze` and `dartrics unused` — auto-explain is default; for post-hoc lookup use `dartrics explain <id> --input report.json`.
* `MetricPolarity.up` removed from the enum — no built-in metric used it. Custom embedder metrics that registered `MetricPolarity.up` will fail to compile; treat as `neutral`.
* `dartrics: { unused: { presets: [...] } }` removed — was a no-op since 0.1.0. Schema rejects the key.

### Other

* `dartrics ai-loop` subcommand added — prints the AI-loop walkthrough; byte-mirrored from `doc/ai-loop.md`.
* `references` field added to every built-in metric, surfacing through `dartrics rules`, AI / md / SARIF reporters, and the explain blocks.
* README rewritten and trimmed (545 → 429 lines).

## 0.2.2

### Bugfixes

* `maximum-nesting-level` no longer counts named-argument closures (Widget builders, event handlers) as a nesting level.
* Summary tables surface snapshot mode and the diff filter so the cache-mode default doesn't render as a regression. `snapshotMode` and `changedFileCount` added at the JSON report root (field additions only; AI/JSON header version unchanged).

## 0.2.1

### Bugfix

* `.pubignore`'s `coverage/` pattern (no leading slash) matched at any depth, so the `0.1.0` and `0.2.0` archives shipped without `lib/src/coverage/coverage_loader.dart` and `lib/src/coverage/lcov_reader.dart`. Anyone who installed from pub.dev hit unresolved-import errors. Pattern is now `/coverage/`; reinstall to recover.

## 0.2.0

* Public-API unused-code detection switched from a simple-name reference graph to the analyzer's resolved element graph — keyed on canonical `Element.id`s. Member granularity added (instance methods, fields, getters / setters, enum values).
* New `--filter <kinds>` CLI flag and matching `unused: { filter: [...] }` YAML key. See `dartrics analyze --help`.
* Auto-rooting for `@override` members, Object dunder names, and members of classes carrying a keep-alive annotation.
* `LibraryElement.exportNamespace` now drives the `excludeExported` root set.

## 0.1.0

First public release. Ships the function / class / library metric battery (see `dartrics rules`), the public-API unused detector, the analyzer plugin (function-level rules), the `--reporter ai` AI-integration surface, and the embeddable Dart API (`FunctionMetric` family + `dartricsVersion`). Operator reference in `doc/manual.md` and `dartrics manual`; AI-loop walkthrough in `doc/ai-loop.md` and `dartrics ai-loop`; wire formats in `schemas/`. Exit codes sysexits-aligned.
