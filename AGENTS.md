# Agent Guidelines

Conventions for AI coding agents (Claude Code, Cursor, Codex, etc.) and human contributors working on this repository. Keep this short and operational; if a rule lives elsewhere (CHANGELOG, README), link rather than duplicate.

## Repository layout

- `bin/dartrics.dart` — minimal CLI entrypoint; defers to `lib/src/entry_point.dart`.
- `lib/main.dart` — analyzer-plugin entrypoint. The filename is **upstream-fixed**: `analysis_server_plugin` requires every plugin to expose `final plugin = ...Plugin()` from `lib/main.dart`, and the analysis-server isolate loads it by that exact path (see [`analysis_server_plugin`'s `doc/writing_a_plugin.md`](https://github.com/dart-lang/sdk/tree/main/pkg/analysis_server_plugin/doc/writing_a_plugin.md)). **Do not rename this file** — the plugin will silently stop being loaded by `dart analyze` and the IDE. The CLI's main entrypoint is unrelated and lives at `bin/dartrics.dart` → `lib/src/entry_point.dart`; if a workspace-symbol search for `main` returns this file, that's why.
- `lib/dartrics.dart` — public API for embedders. Add new exports here when a new model / calculator should be reachable from outside `lib/src/`.
- `lib/src/cli/` — `CommandRunner` plus the `analyze` / `unused` / `report` / `rules` / `regression` / `manual` / `doctor` / `explain` subcommands and the shared option set. `snapshot.dart` and `git_diff.dart` are the storage / VCS adapters. `manual_text.dart` is a const-string mirror of `doc/manual.md`; the parity test in `test/cli/manual_command_test.dart` enforces byte equality so they cannot drift. `doctor_command.dart` exports a pure `diagnose(Config)` so embedders can reuse the same validation rules without spawning the CLI. `explain_command.dart` exposes `findViolation(rawJson, id)` and `readReportBody(input, {stdinSource})` so the reverse-lookup can be driven from a Dart program too.
- `lib/src/analyzer_runner.dart` — sole abstraction over `package:analyzer`. Keep direct analyzer API calls inside this file; the rest of the codebase is shielded from analyzer's frequent breaking changes.
- `lib/src/config/` — YAML loader for the `dartrics:` section in `analysis_options.yaml`.
- `lib/src/coverage/` — lcov.info parser (`lcov_reader.dart`) and the CLI loader (`coverage_loader.dart`).
- `lib/src/lint/` — analyzer plugin: `DartricsPlugin` plus the five `AnalysisRule`s under `rules/` (CC, Cognitive, Max nesting, Number of parameters, Boolean-trap). Each rule wraps a function-level metric calculator and reports through `LintCode` with `{0}`/`{1}` placeholders.
- `lib/src/metrics/{function,class,library}/` — per-scope metric calculators. Each implements `FunctionMetric` / `ClassMetric` / `LibraryMetric`, including the `rationale`, `refactorHints`, `references`, and `polarity` getters.
- `lib/src/metrics/metric_engine.dart` — orchestrator that resolves every Dart file once and runs the registered calculators, attaching coverage / `complexityJustified` to violations when supplied.
- `lib/src/metrics/metric_catalogue.dart` — `defaultMetricThresholds`, `collectRuleDescriptions`, and `findRuleDescription`. Single source of truth for "which metrics ship with what default threshold + rationale"; consumed by `dartrics rules`, auto-explain, `dartrics explain <id>`, and the SARIF reporter so they all stay in sync.
- `lib/src/metrics/flutter_aware.dart` — pure-AST helpers used by both the engine and the plugin to skip noisy widget patterns.
- `lib/src/metrics/test_aware.dart` — pure-path helper that recognises `_test.dart` files under `test/` or `integration_test/` so the engine and the plugin can step aside on size-and-shape lenses for legitimate AAA / group-setUp scaffolding.
- `lib/src/models/` — `AnalysisReport`, `MetricRecord`, `MetricViolation`, `ScopeRef`, `UnusedDeclaration`, `SourceLocation`, `RegressionReport` family, `AnalyzedFile`, `ExplainEntry`. Stable JSON schema lives here.
- `lib/src/regression/` — `RegressionDiff` (pure computation) and `GitWorktree` (the short-lived `git worktree add` adapter for the historical side of the diff).
- `lib/src/reporters/` — `console` / `json` / `md` / `ai` / `sarif` / `regression` / `rules`. `md` and `ai` finalise through `package:dapper`.
- `lib/src/unused/` — public-API reachability graph + BFS detector + code-gen / reflection keep-alive presets. `unused_detector.dart` is the facade with two entry points: the parse-only `detect` (kept for tests / embedders that don't want a real `AnalysisContextCollection`) and the resolved-AST `detectResolved` (the path the CLI actually takes — keys reachability on canonical `Element.id`s, tracks members at instance granularity, auto-roots `@override` / Object dunders, and propagates class-level annotation keep-alive to every member). `resolved_reachability.dart` houses the resolved implementation; `apply.dart` does the `--apply` deletion pass.
- `test/` mirrors `lib/src/` 1-to-1; each metric has a golden test against hand-verified values; each plugin rule has an `AnalysisRuleTest` (analyzer_testing + test_reflective_loader); `cli_flow_test.dart` exercises end-to-end via a temp git repo.

## Workflow before every commit

Run, in this order, and address every finding:

```bash
dart format lib test example
dart analyze lib test example
dart test
dart pub run coverage:test_with_coverage   # 100% line coverage required
```

Why each step:

- `dart format` — Dart 3.7+ tall-style formatter. Don't let formatter drift accumulate; never commit unformatted code. Tall-style sometimes wraps `if` bodies onto a new line, which then trips `curly_braces_in_flow_control_structures` — wrap with explicit braces.
- `dart analyze` — strict lints are on (`strict-casts`, `strict-inference`, `strict-raw-types`, `prefer_relative_imports`, `require_trailing_commas`, etc.); fix info-level findings too. The full-project `dart analyze` (no path arg) loads the dartrics plugin in an isolate and may flake; scope to `lib test example` for clean runs in CI / sandbox.
- `dart test` — every metric has a golden test; new metrics need one.
- 100% line coverage on `lib/` is treated as a **correctness signal**: an uncovered line is read as evidence of dead code that should be removed, not just a coverage gap. Fix by deleting the unreachable branch before adding a contrived test.

## Adding a new metric

1. Pick the right scope file under `lib/src/metrics/`.
2. Implement the calculator, anchoring its docstring to the original paper / spec. Don't paraphrase the formula; quote it.
3. Implement the metadata getters every metric must expose:
   - `id` — stable kebab-case identifier (used as JSON key and threshold key).
   - `rationale` — one paragraph anchored in the original paper. Used by `dartrics rules`, auto-explain, and `dartrics explain <id>`.
   - `refactorHints` — list of single-sentence imperative refactor moves.
   - `references` — primary-source citations (paper / book / spec). Return `const []` if the metric has no published anchor.
   - `polarity` — `MetricPolarity.down` (lower is better, the default) or `neutral` (regression diff surfaces deltas without classifying).
4. Register the calculator in the corresponding `default_*_metrics.dart` list so the engine picks it up.
5. Add a golden test in `test/metrics/.../<metric>_test.dart` with hand-verified values from a paper example or a small fixture you can verify by inspection.
6. Update `README.md`'s metric table.
7. Update `CHANGELOG.md` under the next-release section.
8. If the metric is function-level and cheap, also add an `AnalysisRule` under `lib/src/lint/rules/` so it surfaces through the analyzer plugin (see `cyclomatic_complexity_rule.dart` as a template) and register it in `DartricsPlugin.register`. Heavier metrics stay CLI-only.

## Adding a new reporter

1. Create `lib/src/reporters/<name>_reporter.dart` implementing `Reporter`.
2. Register it in `pickReporter` in `lib/src/reporters/reporters.dart`.
3. Allow `<name>` in the `--reporter` option's `allowed` list inside `lib/src/cli/common_options.dart`.
4. Add a test that exercises it against `buildSampleReport()` from `test/reporters/sample_report.dart`.

## Configuration

The CLI and analyzer plugin both read from a `dartrics:` section inside `analysis_options.yaml` (override with `--config <path>` for the CLI). When extending the schema, keep `lib/src/config/config.dart`, `lib/src/config/config_loader.dart`, and `lib/src/lint/lint_options.dart` (the plugin-side parser) in sync, plus the `## Configuration` section in `README.md`.

## Commits

- Conventional Commits 1.0.0 — `<type>[scope]: <description>` plus body and footers when needed. Common types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `build`, `ci`, `perf`, `style`.
- One commit per logical unit. Don't bundle reformatting with feature work; the `style: apply dart format` commit pattern is reserved for cases where formatter drift slipped through and needs catching up.
- All commits must be SSH-signed in this repo. The 1Password SSH agent isn't reachable from inside the Claude Code sandbox; sign-requesting `git commit` / `git rebase` invocations need `dangerouslyDisableSandbox: true`. If signing has to be deferred (agent unavailable), commit with `--no-gpg-sign` and re-sign later with `git rebase --exec 'git commit --amend --no-edit -S' <base>`.
- Co-author Claude commits with a `Co-Authored-By: <model name> <noreply@anthropic.com>` footer (existing history uses `Claude Opus 4.7 (1M context)`; match the model the session is actually running).
- Local `git log --show-signature` may print "No signature" because `gpg.ssh.allowedSignersFile` isn't configured in this repo; that's a verification-config issue, not a signing failure. Confirm by checking for `gpgsig -----BEGIN SSH SIGNATURE-----` via `git cat-file -p HEAD`.

## Markdown style

- One bullet = one source line. No mid-sentence soft-wraps; let the renderer reflow.
- Block code, nested paragraphs under a bullet, and headings are unaffected.

## Scratch space

`./tmp/` is gitignored. Put plans, intermediate artefacts, and debug scripts there. Nothing under `tmp/` may be referenced from tracked files (README, source, comments) — those references would dead-end for fresh clones.

## Skills

`.claude/skills/dart-cli-app-best-practices/` is bundled from `kevmoo/dash_skills`. Honor its entrypoint-structure / `exitCode`-vs-`exit()` / cross-platform-path guidance for any change touching `bin/` or CLI plumbing.
