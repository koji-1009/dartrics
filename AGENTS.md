# Agent Guidelines

Conventions for AI coding agents (Claude Code, Cursor, Codex, etc.) and human contributors working on this repository. Operational rules first; rationale second. If a rule lives elsewhere (CHANGELOG, README, `doc/manual.md`, `doc/calibration.md`), link rather than duplicate.

## Repository layout

- `bin/dartrics.dart` — minimal CLI entrypoint; defers to `lib/src/entry_point.dart`.
- `lib/main.dart` — analyzer-plugin entrypoint. The filename is **upstream-fixed**: `analysis_server_plugin` requires every plugin to expose `final plugin = ...Plugin()` from `lib/main.dart`, and the analysis-server isolate loads it by that exact path (see [`analysis_server_plugin`'s `doc/writing_a_plugin.md`](https://github.com/dart-lang/sdk/tree/main/pkg/analysis_server_plugin/doc/writing_a_plugin.md)). **Do not rename this file** — the plugin will silently stop being loaded by `dart analyze` and the IDE. The CLI's main entrypoint is unrelated and lives at `bin/dartrics.dart` → `lib/src/entry_point.dart`; if a workspace-symbol search for `main` returns this file, that's why.
- `lib/dartrics.dart` — public API for embedders. Add new exports here when a new model / calculator should be reachable from outside `lib/src/`.
- `lib/src/cli/` — `CommandRunner` plus the `analyze` / `unused` / `inspect` / `report` / `rules` / `regression` / `manual` / `ai-loop` / `doctor` subcommands. `manual_text.dart` and `ai_loop_text.dart` are const-string mirrors of `doc/manual.md` and `doc/ai-loop.md`; parity tests in `test/cli/` enforce byte equality so they cannot drift.
- `lib/src/analyzer_runner.dart` — sole abstraction over `package:analyzer`. Keep direct analyzer API calls inside this file; the rest of the codebase is shielded from analyzer's frequent breaking changes.
- `lib/src/config/` — YAML loader for the `dartrics:` section in `analysis_options.yaml`.
- `lib/src/coverage/` — lcov.info parser (`lcov_reader.dart`) and the CLI loader (`coverage_loader.dart`).
- `lib/src/lint/` — analyzer plugin: `DartricsPlugin` plus the three `AnalysisRule`s under `rules/` (CC, Cognitive, Number of parameters). Each rule wraps a function-level metric calculator and reports through `LintCode` with `{0}`/`{1}` placeholders.
- `lib/src/metrics/{function,class,library}/` — per-scope metric calculators. Each implements `FunctionMetric` / `ClassMetric` / `LibraryMetric`, including `rationale`, `refactorHints`, `references`, and `polarity` getters.
- `lib/src/metrics/metric_engine.dart` — orchestrator that resolves every Dart file once and runs the registered calculators, attaching coverage / `complexityJustified` to violations when supplied.
- `lib/src/metrics/metric_catalogue.dart` — `defaultMetricThresholds`, `collectRuleDescriptions`, and `findRuleDescription`. Single source of truth for "which metrics ship with what default threshold + rationale"; consumed by `dartrics rules`, auto-explain, and the SARIF reporter so they all stay in sync.
- `lib/src/metrics/flutter_aware.dart` — pure-AST helpers used by both the engine and the plugin to skip `number-of-parameters` on widget constructors.
- `lib/src/metrics/test_aware.dart` — pure-path helper that recognises `_test.dart` files under `test/` or `integration_test/` so the engine can step aside on size-and-shape lenses for legitimate AAA scaffolding.
- `lib/src/models/` — `AnalysisReport`, `MetricRecord`, `MetricViolation`, `ScopeRef`, `UnusedDeclaration`, `SourceLocation`, `RegressionReport` family, `AnalyzedFile`, `ExplainEntry`. Stable JSON schema lives here.
- `lib/src/regression/` — `RegressionDiff` (pure computation) and `GitWorktree` (the short-lived `git worktree add` adapter for the historical side of the diff).
- `lib/src/reporters/` — `console` / `json` / `md` / `ai` / `sarif` / `regression` / `rules`. `md` and `ai` finalise through `package:dapper`.
- `lib/src/unused/` — public-API reachability graph + BFS detector + code-gen / reflection keep-alive presets. `unused_detector.dart` is the facade; `resolved_reachability.dart` houses the resolved-AST implementation; `apply.dart` does the `--apply` deletion pass.
- `test/` mirrors `lib/src/` 1-to-1; each metric has a golden test against hand-verified values; each plugin rule has an `AnalysisRuleTest` (analyzer_testing + test_reflective_loader); `cli_flow_test.dart` exercises end-to-end via a temp git repo.

## Workflow before every commit

Run, in this order, and address every finding:

```bash
dart format lib test example
dart analyze lib test example
dart test
dart pub run coverage:test_with_coverage   # 100% line coverage required
```

- `dart format` — Dart 3.7+ tall-style formatter. Don't let formatter drift accumulate; never commit unformatted code. Tall-style sometimes wraps `if` bodies onto a new line, which then trips `curly_braces_in_flow_control_structures` — wrap with explicit braces.
- `dart analyze` — strict lints are on (`strict-casts`, `strict-inference`, `strict-raw-types`, `prefer_relative_imports`, `require_trailing_commas`, etc.); fix info-level findings too. The full-project `dart analyze` (no path arg) loads the dartrics plugin in an isolate and may flake; scope to `lib test example` for clean runs.
- `dart test` — every metric has a golden test; new metrics need one.
- 100% line coverage on `lib/` is treated as a **correctness signal**: an uncovered line is read as evidence of dead code that should be removed, not a coverage gap. Fix by deleting the unreachable branch before adding a contrived test.

## Dogfood gate

CI runs `dart run bin/dartrics.dart analyze --root . --snapshot none --fatal-warnings` on every push and PR; the dartrics codebase must clear its own metric battery to merge. Reproduce locally with the same command — `--fatal-warnings` is what makes a lingering warning exit non-zero.

If a lens fires on idiomatic Dart code in this repo, the first move is **lens correction** (or its skip rule), not dismiss. A lens that over-fires on the canonical idiomatic-Dart codebase will over-fire elsewhere too — adjust the lens, not the call site.

## Code style

- snake_case filenames in `lib/src/`. Don't prefix files with underscore — Dart privacy is identifier-scoped, not file-scoped, so a leading-underscore filename gains no visibility benefit and just disrupts tooling.
- Match the surrounding code's voice. Don't introduce a new style or comment density alongside existing files.
- Dart 3 dot-shorthand is welcome anywhere the target type can be inferred from context — including argument positions where the parameter type names the enum (`SnapshotConfig(mode: .cache)`). Reading `.cache` next to a parameter typed `SnapshotMode` adds no ambiguity for either human or AI readers.
- No defensive in-source comments when removing code. The "why" lives in the commit body and `git log`; leaving a tombstone comment in the source pollutes future reads.

## Documentation conventions

- README, AGENTS, CHANGELOG, and everything under `doc/` are **English-only**. Conversation in issue threads or PR review can be any language; tracked artefacts stay English to keep the codebase consumable by international contributors and by AI agents trained on English corpora.
- One markdown bullet = one source line. Don't soft-wrap mid-sentence; let the renderer reflow.
- Don't reference `tmp/` paths from tracked files. The directory is gitignored and any reference would dead-end for fresh clones.
- Don't cite content under `tmp/done/` or other archived-draft locations as authoritative. Those are scratch material; nothing is committed until it lands in a tracked file. Version labels and tier numbers in archived drafts are not commitments.
- README is "back of the box" — philosophy, what it does, the metric inventory at a glance. Detailed flag mechanics, dismissal protocol, and configuration reference live in `doc/manual.md` (mirrored as `dartrics manual`); the refactor walkthrough lives in `doc/ai-loop.md` (mirrored as `dartrics ai-loop`); citation audit lives in `doc/calibration.md`. When adding new operator detail, prefer `doc/manual.md` over README.

## Adding a new metric

1. Pick the right scope file under `lib/src/metrics/`.
2. Implement the calculator, anchoring its docstring to the original paper / spec. Don't paraphrase the formula; quote it.
3. Implement the metadata getters every metric must expose:
   - `id` — stable kebab-case identifier (used as JSON key and threshold key).
   - `rationale` — one paragraph anchored in the original paper. Used by `dartrics rules` and auto-explain.
   - `refactorHints` — list of single-sentence imperative refactor moves.
   - `references` — primary-source citations (paper / book / spec). Verify each citation against the original source; do not rely on secondary references.
   - `polarity` — `MetricPolarity.down` (lower is better, the default) or `neutral` (regression diff surfaces deltas without classifying).
4. Register the calculator in the corresponding `default_*_metrics.dart` list so the engine picks it up.
5. Add a golden test in `test/metrics/.../<metric>_test.dart` with hand-verified values from a paper example or a small fixture you can verify by inspection.
6. Update `README.md`'s "Provided metrics" table and `doc/manual.md`'s "The lens battery" table.
7. If the metric deviates from its source's literal definition (e.g. counting only positional parameters where the source counts all), document the deviation in `doc/calibration.md`.
8. Update `CHANGELOG.md` under the next-release section.
9. If the metric is function-level and cheap, also add an `AnalysisRule` under `lib/src/lint/rules/` so it surfaces through the analyzer plugin (see `cyclomatic_complexity_rule.dart` as a template) and register it in `DartricsPlugin.register`. Heavier metrics stay CLI-only.

## Adding a new reporter

1. Create `lib/src/reporters/<name>_reporter.dart` implementing `Reporter`.
2. Register it in `pickReporter` in `lib/src/reporters/reporters.dart`.
3. Allow `<name>` in the `--reporter` option's `allowed` list inside `lib/src/cli/common_options.dart`.
4. Add a test that exercises it against `buildSampleReport()` from `test/reporters/sample_report.dart`.

## Configuration

The CLI and analyzer plugin both read from a `dartrics:` section inside `analysis_options.yaml` (override with `--config <path>` for the CLI). When extending the schema, keep `lib/src/config/config.dart`, `lib/src/config/config_loader.dart`, and `lib/src/lint/lint_options.dart` (the plugin-side parser) in sync with `schemas/dartrics-config.schema.json`.

## Commits

- Conventional Commits 1.0.0 — `<type>[scope]: <description>` plus body and footers when needed. Common types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `build`, `ci`, `perf`, `style`. Use `feat!:` (or a `BREAKING CHANGE:` footer) for breaking changes.
- One commit per logical unit. Don't bundle reformatting with feature work; the `style: apply dart format` commit pattern is reserved for cases where formatter drift slipped through and needs catching up.
- Sign your commits if your local git is configured for signing. `gpg.ssh.allowedSignersFile` isn't checked into this repo, so `git log --show-signature` may print "No signature" locally even on signed commits — confirm via `git cat-file commit HEAD | grep gpgsig`.
- Keep commit messages and PR bodies free of pre-merge hygiene stamps (test counts, coverage percentages, "all tests pass", "dry-run clean"). Those belong in CI status, not in the historical artefact. Audit recent commits before composing — match the project's existing voice.
- AI-authored commits should carry a `Co-Authored-By: <model name> <noreply@anthropic.com>` footer (existing history uses `Claude Opus 4.7 (1M context)`; match the model the session is actually running).

## Release flow

1. Bump `version:` in `pubspec.yaml` and `dartricsVersion` in `lib/src/version.dart` in lockstep — they're separate sources by design (the version string is compiled into the binary), so they drift if you forget one.
2. Add a `## X.Y.Z` section to `CHANGELOG.md` covering every breaking change, citation correction, and feature.
3. Verify `.pubignore` excludes `test/`, `tool/`, `coverage/`, `.claude/`, `tmp/`, `AGENTS.md`, and any other dev-only artefact. Run `dart pub publish --dry-run` to confirm the package contents.
4. The release commit is `chore(release): X.Y.Z` and is the final commit on a `release/vX.Y.Z` branch. Merge via PR.
5. Pre-1.0, breaking changes ship in minor versions (Dart pub convention). Mark them with `feat!:` and a `BREAKING CHANGE:` footer in the commit body.

## Scratch space

`./tmp/` is gitignored. Put plans, intermediate artefacts, and debug scripts there. Nothing under `tmp/` may be referenced from tracked files (README, source, comments) — those references would dead-end for fresh clones.
