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

- **Auto-explain by default** — rationale, refactor hints, and primary-source citation ride alongside every fired metric, so an agent reads the *why* without a second tool call.
- **Stable IDs across runs** — every violation carries a 16-hex-char id (`sha256("<file>|<scope>|<metric>")`), reappearing across runs so AI loops can detect "my fix didn't take". Surfaces as `partialFingerprints.dartrics/v1` in SARIF.
- **Docs in the binary** — `dartrics manual` and `dartrics ai-loop` print the operator's reference and the four-station walkthrough; `dart pub global activate dartrics` is enough, no separate doc download.

## Install

```bash
dart pub global activate dartrics
```

## Quick start

```bash
# Token-efficient YAML-ish report optimised for LLM consumption.
dartrics analyze lib/ --reporter ai | claude -p "Refactor the threshold violations"

# After the agent applies a fix: confirm metrics actually improved.
dartrics regression --before HEAD~1 --after HEAD --reporter ai

# Read the operator's manual or the AI-loop walkthrough in the terminal.
dartrics manual
dartrics ai-loop
```

## Subcommands

| Command | Purpose |
| --- | --- |
| `analyze` | Every metric + the public-API unused detector. |
| `unused` | Public-API reachability only (fast path). |
| `report <input.json>` | Re-emit a previously saved JSON report in another format. |
| `rules` | Catalogue every metric with rationale, refactor hints, and references. |
| `regression` | Compare metrics between two git states; classify each delta as improved / regressed / unchanged / added / removed. |
| `manual` | Print the operator's manual (mirrors [`doc/manual.md`](doc/manual.md)). |
| `ai-loop` | Print the AI-loop walkthrough (mirrors [`doc/ai-loop.md`](doc/ai-loop.md)). |
| `doctor` | Validate the `dartrics:` block in `analysis_options.yaml`. |

Each subcommand only exposes the flags it actually consumes — `dartrics <command> --help` lists them. Full flag reference, dismissal mechanics, coverage / snapshot / regression details, and the refactor / dismiss decision tree all live in [`dartrics manual`](doc/manual.md) and [`dartrics ai-loop`](doc/ai-loop.md).

## Provided metrics

dartrics ships a curated set anchored to published sources. For the audit trail — selection principles, deviations from the cited definitions, off-by-default rationale — see [`doc/calibration.md`](doc/calibration.md).

Each metric exposes `rationale`, `refactorHints`, `references` (the primary source — McCabe 1976, Hitz & Montazeri 1995, Martin 1994, …), and `polarity` (`down` / `neutral`). All four surface through `dartrics rules` and the AI / md / SARIF reporters so an agent can verify a metric against its original paper rather than paraphrasing from training data.

Lenses marked **off** ship disabled by default; opt in via `dartrics: { metrics: { <id>: { enabled: true } } }`. A `—` in **Default warning** means the lens emits a measurement but fires no warning until you set a threshold via `dartrics: { metrics: { <id>: { warning: <n> } } }`.

### Function / method level

| Metric                          | Reference               | Default warning |
| ------------------------------- | ----------------------- | --------------- |
| Cyclomatic Complexity           | McCabe 1976             | 10              |
| Cognitive Complexity            | SonarSource 2017 (rev.) | 15              |
| Number Of Parameters            | Fowler 1999             | 4               |
| Source Lines Of Code            | Boehm 1981              | —               |
| Method Length **off**           | Beck 1996               | opt-in          |
| Halstead Volume **off**         | Halstead 1977           | opt-in          |

### Class level

| Metric                     | Reference                                    | Default warning |
| -------------------------- | -------------------------------------------- | --------------- |
| Number Of Methods          | Lorenz & Kidd 1994; CK 1994                  | —               |
| Weighted Methods Per Class | CK 1994                                      | —               |
| LCOM4                      | Hitz & Montazeri 1995                        | —               |
| Coupling Between Objects   | CK 1994                                      | —               |
| Response For a Class       | CK 1994                                      | —               |
| Class Length               | Beck 1996; Fowler 1999; Lippert & Roock 2006 | —               |

### Library / file level (Martin 1994)

Polarity `neutral`; values rank change-impact rather than fire as Pain/Uselessness verdicts (see [`doc/calibration.md`](doc/calibration.md)).

| Metric                                  | Notes                                                                   | Default warning |
| --------------------------------------- | ----------------------------------------------------------------------- | --------------- |
| Efferent Coupling (Ce)                  | distinct project-internal + `package:` dependencies (excludes `dart:*`) | —               |
| Afferent Coupling (Ca)                  | incoming internal-import edges                                          | —               |
| Instability (I)                         | `Ce / (Ca + Ce)`; informational, surfaces drift in change-impact ranking | —              |

## Configuration

Minimal `analysis_options.yaml`:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/koji-1009/dartrics/main/schemas/dartrics-config.schema.json

dartrics:
  metrics:
    cyclomatic-complexity:
      warning: 10
      error: 20
    cognitive-complexity:
      warning: 15
  exclude:
    - "lib/generated/**"
```

The `dartrics:` section is read by both the CLI and the analyzer plugin. The `# yaml-language-server` directive turns on autocomplete + typo detection in editors with [yaml-language-server](https://github.com/redhat-developer/yaml-language-server) integration. Every key (per-metric thresholds, dismissals, snapshot mode, unused-detector filters) is documented in [`schemas/dartrics-config.schema.json`](schemas/dartrics-config.schema.json) and explained in [`dartrics manual`](doc/manual.md).

## Analyzer plugin

`dartrics` ships its own analyzer plugin so the three lightweight function-level rules surface inline in `dart analyze` and the IDE.

```yaml
# analysis_options.yaml in your project
plugins:
  dartrics:
```

After saving, restart the analysis server. Three rules ship by default:

| Rule                             | Default threshold |
| -------------------------------- | ----------------- |
| `dartrics_cyclomatic_complexity` | 10                |
| `dartrics_cognitive_complexity`  | 15                |
| `dartrics_number_of_parameters`  | 4                 |

Heavier metrics (LCOM4, CBO, RFC, library coupling) and the public-API unused detector intentionally stay CLI-only because they need a project-wide index that an analysis-server plugin can't maintain efficiently per file.

## Documentation

- [`dartrics manual`](doc/manual.md) — operator's reference: every flag, dismissal mechanics, refactor / dismiss decision tree, Flutter-aware and test-aware modes, exit codes.
- [`dartrics ai-loop`](doc/ai-loop.md) — four-station walkthrough of one full refactor iteration with sample prompts.
- [`doc/calibration.md`](doc/calibration.md) — citation audit, selection principles, counting-rule deviations.
- [`schemas/`](schemas/) — JSON Schema files: `dartrics-config.schema.json` for `analysis_options.yaml`'s `dartrics:` block, `dartrics-report.schema.json` for the JSON reporter output, `dartrics-dismissals.schema.json` for the dismissals sidecar. All draft-2020-12.

## Output formats

`--reporter` accepts `console` (default), `json` (stable schema, see [`schemas/dartrics-report.schema.json`](schemas/dartrics-report.schema.json)), `md` (PR comments / issue bodies), `ai` (token-efficient YAML-ish bundle starting with `# dartrics ai-report v1`), and `sarif` (SARIF 2.1.0 for GitHub Code Scanning / GitLab).

## Embedding

`lib/dartrics.dart` is intentionally tight — it exposes only the function-level metric calculators so a custom CI bot or editor extension can compute one metric on a parsed `CompilationUnit` without spinning up the full engine.

| What you get | Names |
| --- | --- |
| Function-level metric calculators | `CyclomaticComplexity`, `CognitiveComplexity`, `NumberOfParameters`, `MethodLength`, `SourceLinesOfCode`, `HalsteadCounts` / `HalsteadVolume` |
| Calculator interface | `FunctionMetric`, `FunctionMetricInput`, `MetricPolarity` |
| Version string | `dartricsVersion` |

Anything not in this table is CLI-only and unsupported as a Dart import; reach for `dartrics analyze --reporter json` instead. `example/main.dart` shows a 30-line standalone embedding against `CyclomaticComplexity`.

## Limitations

- **The analyzer plugin covers only the three function-level rules** (CC, Cognitive, Number of parameters). LCOM4 / CBO / RFC / library coupling and the unused detector are CLI-only because they need a project-wide index that the analyzer-plugin API can't maintain efficiently per-file.
- **Built-in metric set is curated.** See [`doc/calibration.md`](doc/calibration.md) for the selection principles.
- **Per-file Martin granularity.** `efferent-coupling` / `afferent-coupling` / `instability` ship as change-impact rankings rather than Pain/Uselessness verdicts (polarity `neutral`, no default warning). See [`doc/calibration.md`](doc/calibration.md).
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
