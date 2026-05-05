# Agent Guidelines

Conventions for AI coding agents (Claude Code, Cursor, Codex, etc.) and human contributors working on this repository. Keep this short and operational; if a rule lives elsewhere (CHANGELOG, design doc), link rather than duplicate.

## Repository layout

- `bin/dartrics.dart` — minimal CLI entrypoint; defers to `lib/src/entry_point.dart`.
- `lib/main.dart` — analyzer-plugin entrypoint; the analysis-server reads `final plugin = DartricsPlugin()` from here when a project's `analysis_options.yaml` enables `plugins: dartrics`.
- `lib/src/cli/` — `CommandRunner` + `analyze` / `unused` / `report` subcommands and the shared option set.
- `lib/src/analyzer_runner.dart` — sole abstraction over `package:analyzer`. Keep direct analyzer API calls inside this file; the rest of the codebase is shielded from analyzer's frequent breaking changes.
- `lib/src/config/` — YAML loader for the CLI's `dartrics:` section in `analysis_options.yaml`.
- `lib/src/lint/` — analyzer plugin: `DartricsPlugin` plus the four `AnalysisRule`s under `rules/`. Each rule wraps a function-level metric calculator and reports through `LintCode` with `{0}`/`{1}` placeholders.
- `lib/src/metrics/{function,class,library}/` — per-scope metric calculators. Each implements `FunctionMetric` / `ClassMetric` / `LibraryMetric`.
- `lib/src/metrics/metric_engine.dart` — orchestrator that resolves every Dart file once and runs the registered calculators.
- `lib/src/models/` — `AnalysisReport`, `MetricRecord`, `ScopeRef`, `UnusedDeclaration`, `SourceLocation`. Stable JSON schema lives here.
- `lib/src/reporters/` — `console` / `json` / `md` / `ai` / `sarif`. `md` and `ai` finalise through `package:dapper`.
- `lib/src/unused/` — public-API reachability graph + BFS detector.
- `test/` mirrors `lib/src/` 1-to-1; each metric has a golden test against hand-verified values; each plugin rule has an `AnalysisRuleTest` (analyzer_testing + test_reflective_loader).

## Workflow before every commit

Run, in this order, and address every finding:

```bash
dart format lib test
dart analyze
dart test
dart pub run coverage:test_with_coverage   # 100% line coverage required
```

Why each step:

- `dart format` — Dart 3.7+ tall-style formatter. Don't let formatter drift accumulate; never commit unformatted code. Tall-style sometimes wraps `if` bodies onto a new line, which then trips `curly_braces_in_flow_control_structures` — wrap with explicit braces.
- `dart analyze` — strict lints are on (`strict-casts`, `strict-inference`, `strict-raw-types`, `prefer_relative_imports`, `require_trailing_commas`, etc.); fix info-level findings too.
- `dart test` — every metric has a golden test; new metrics need one.
- 100% line coverage on `lib/` is treated as a **correctness signal**: an uncovered line is read as evidence of dead code that should be removed, not just a coverage gap. Fix by deleting the unreachable branch before adding a contrived test.

## Adding a new metric

1. Pick the right scope file under `lib/src/metrics/`.
2. Implement the calculator, anchoring its docstring to the original paper / spec. Don't paraphrase the formula; quote it.
3. Register it in the corresponding `_default_*_metrics.dart` list so the engine picks it up.
4. Add golden tests in `test/metrics/.../<metric>_test.dart` with hand-verified values from a paper example or a small fixture you can verify by inspection.
5. Update `README.md`'s metric table.
6. Update `CHANGELOG.md` under the next-release section.
7. If the metric is function-level and cheap, also add an `AnalysisRule` under `lib/src/lint/rules/` so it surfaces through the analyzer plugin (see `cyclomatic_complexity_rule.dart` as a template) and register it in `DartricsPlugin.register`. Heavier metrics stay CLI-only.

## Adding a new reporter

1. Create `lib/src/reporters/<name>_reporter.dart` implementing `Reporter`.
2. Register it in `pickReporter` in `lib/src/reporters/reporters.dart`.
3. Allow `<name>` in the `--reporter` option's `allowed` list inside `lib/src/cli/common_options.dart`.
4. Add a test that exercises it against `buildSampleReport()` from `test/reporters/_test_report.dart`.

## Configuration

The CLI reads from a `dartrics:` section inside `analysis_options.yaml` (default; override with `--config <path>`). Keep the schema doc in `README.md` in sync with `lib/src/config/config.dart` and `lib/src/config/config_loader.dart`. The analyzer plugin currently uses thresholds baked into each rule class; user-configurable thresholds are on the roadmap and will land in `lib/src/lint/` alongside the YAML loader.

## Commits

- Conventional Commits 1.0.0 — `<type>[scope]: <description>` plus body and footers when needed. Common types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `build`, `ci`, `perf`, `style`.
- One commit per logical unit. Don't bundle reformatting with feature work; the `style: apply dart format` commit pattern is reserved for cases where formatter drift slipped through and needs catching up.
- All commits must be SSH-signed in this repo. The 1Password SSH agent isn't reachable from inside the Claude Code sandbox; sign-requesting `git commit` / `git rebase` invocations need `dangerouslyDisableSandbox: true`. If signing has to be deferred (agent unavailable), commit with `--no-gpg-sign` and re-sign later with `git rebase --root --exec 'git commit --amend --no-edit -S'`.
- Co-author Claude commits with the `Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>` footer.
- Local `git log --show-signature` may print "No signature" because `gpg.ssh.allowedSignersFile` isn't configured in this repo; that's a verification-config issue, not a signing failure. Confirm by checking for `gpgsig -----BEGIN SSH SIGNATURE-----` via `git cat-file commit HEAD`.

## Markdown style

- One bullet = one source line. No mid-sentence soft-wraps; let the renderer reflow.
- Block code, nested paragraphs under a bullet, and headings are unaffected.

## Scratch space

`./tmp/` is gitignored. Put plans, intermediate artefacts, and debug scripts there. Nothing under `tmp/` may be referenced from tracked files (README, source, comments) — those references would dead-end for fresh clones.

## Skills

`.claude/skills/dart-cli-app-best-practices/` is bundled from `kevmoo/dash_skills`. Honor its entrypoint-structure / `exitCode`-vs-`exit()` / cross-platform-path guidance for any change touching `bin/` or CLI plumbing.
