# Changelog

## 0.1.0

### Added

- Project scaffold: CLI entrypoint, `analyze` / `unused` / `report` subcommands,
  configuration loader for `analysis_options.yaml`, analyzer abstraction layer,
  JSON and console reporters.
- Function-level metrics: cyclomatic complexity (McCabe 1976), cognitive
  complexity (Sonar 2018), Halstead volume / difficulty / effort
  (Halstead 1977), maintainability index (Oman 1992), maximum nesting level,
  number of parameters, source lines of code, method length.
- `MetricEngine` walks every resolved compilation unit and computes the full
  default metric set for each function / method / constructor declaration,
  attaching configurable threshold-based violations.
- Class-level metrics: NOM, WMC (Chidamber & Kemerer 1994), LCOM4
  (Hitz & Montazeri 1995, connected-component variant), DIT, NOC,
  Class Length. The engine builds a project-wide `ClassIndex` so DIT
  and NOC can resolve direct supertype/subtype links across files.
- Coupling metrics: CBO and RFC at class scope; Ca / Ce / Instability /
  Abstractness / Distance from main sequence at library scope (Martin
  1994). The engine builds a `LibraryIndex` of project-internal import
  edges to drive Ca/Ce, and counts abstract classes + mixins for `A`.
- Public-API unused-code detection: BFS reachability over a name-based
  reference graph rooted at `main`, `@pragma('vm:entry-point')`, and
  `lib/` exports (when `excludeExported` is enabled, the detector also
  follows `export ... show ...` clauses so re-exported `lib/src/`
  declarations stay reachable). Reports unused public functions,
  classes, mixins, extensions, typedefs, enums, and top-level fields.
  `dartrics analyze` emits both metrics and unused; `dartrics unused`
  is the unused-only fast path.
- Reporters: `md` (Markdown for PR comments, finalised through
  `package:dapper`'s `formatMarkdown`), `ai` (LLM-optimised YAML-ish
  with snippet windows, finalised through `formatYaml`), and `sarif`
  (SARIF 2.1.0 envelope ingestable by GitHub Code Scanning / GitLab).
- Working analyzer plugin via `analysis_server_plugin` (Dart 3.10+): `lib/main.dart` is the entrypoint discovered by the analysis-server, `DartricsPlugin` registers four lightweight `AnalysisRule`s (cyclomatic complexity / cognitive complexity / maximum nesting level / number of parameters) as default-on warnings. Users opt in by adding `plugins: dartrics` to their `analysis_options.yaml`. Heavier metrics (LCOM4, CBO, RFC, library coupling) and the public-API unused detector remain CLI-only because they require a project-wide index.
- Plugin reads the same `dartrics:` section as the CLI. Each rule's threshold can be overridden via `dartrics: { metrics: { <metric-id>: { warning: <n> } } }` (or the bare-integer short form). Defaults apply when the section is missing or malformed. Plugin diagnostics surface at INFO severity in the current analyzer pipeline; non-INFO `LintCode` severities crash the analysis-server isolate (documented as a known upstream constraint).
- Opt-in code-gen keep-alive presets (`freezed`, `json_serializable`, `dart_mappable`, `go_router_builder`, `auto_route`) under `dartrics.unused.presets:`. Each preset expands to a curated annotation list that the unused-public-API detector treats as keep-alive roots, so source classes aren't flagged on a fresh checkout when their `.g.dart` / `.freezed.dart` partner hasn't been generated yet. Unknown preset names are silently ignored.
- Curated metric set: removed `depth-of-inheritance-tree` and `number-of-children` (CK 1994 metrics that don't fit Dart's mixin / composition-over-inheritance culture); switched `halstead-volume`, `halstead-difficulty`, `halstead-effort`, and `maintainability-index` to **off-by-default** with opt-in via `dartrics: { metrics: { <id>: { enabled: true } } }` (or the bare-bool short form `<id>: true`). `MetricThresholds` now carries an `enabled` field; `FunctionMetric` / `ClassMetric` / `LibraryMetric` expose `defaultEnabled` so each calculator can declare whether it's part of the default set.
- Generated Dart files are now skipped during file collection by default (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.config.dart`, `*.mocks.dart`, `*.pb.dart`, `*.pbenum.dart`, `*.pbgrpc.dart`, `*.pbjson.dart`, `*.pbserver.dart`, `*.gen.dart`). Metrics on machine-generated source were noise — values change every time `dart run build_runner build` runs and the human didn't author the code. Override with `AnalyzerRunner(includeGenerated: true)` if you really want them.
- `analyze` and `unused` accept `--since <git-ref>` to restrict their output to declarations whose owning `.dart` file changed between `<ref>` and `HEAD`. The pipeline still resolves the full project so cross-file analysis (LCOM4, Martin coupling, public-API reachability) stays accurate; only the *emitted* records are filtered. Designed for AI-driven PR review and diff-scoped CI gates: `dartrics analyze --since origin/main --reporter ai | claude -p '...'`. Shells out to `git diff --name-only --diff-filter=AMR <ref>...HEAD -- '*.dart'`; missing git or unresolved refs exit with `65 EX_DATAERR`.
- `lib/dartrics.dart` exposes the function-level metric calculator classes alongside the existing report shapes for embedders.

### Changed

- Stricter `analysis_options.yaml` for both packages
  (`strict-casts: true`, `strict-inference: true`, `strict-raw-types:
  true`, `prefer_relative_imports`, `require_trailing_commas`, etc.).
- Refactored `Lcom4.compute` (split into `_ClassView` + `_Accesses`
  + `_UnionFind` extension), `LibraryIndex.build` (split per-directive
  / per-class counter helpers), and the unused-detector entry-point
  collector for lower cyclomatic + cognitive complexity.

### Fixed

- `ConfigException` now exits with `78 EX_CONFIG` and `UsageException`
  with `64 EX_USAGE` instead of being swallowed by the
  `runZonedGuarded` `EX_SOFTWARE` fall-through.
- Cognitive complexity no longer double-counts a nested local function
  (the wrapping `FunctionDeclaration` is the bookkeeping unit).
- Maximum nesting level no longer descends into local-function bodies
  (those bodies are measured separately by the engine).

### Engineering

- `FunctionMetricInput` adopts a strict `fromDeclaration` factory and
  removes the dead `body` / `parameters` null-fallback branches; every
  metric now consumes a non-nullable `body`.
- LCOM4's union-find drops the rank-balancing branches that were never
  reached on real-world class inputs.
- `dartrics_lint`'s `DiagnosticSeverity` shrank to `{warning, error}`
  (the unused `info` value was dead code).
- 100% line coverage on both `dartrics` and `dartrics_lint` (verified
  via `dart pub run coverage:test_with_coverage`). The detector itself
  flagged the formerly-unused `MetricLevel` enum on first dogfooding.
