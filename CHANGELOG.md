# Changelog

## Unreleased

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
- New `packages/dartrics_lint/` analyzer-plugin package — exposes the
  lightweight function-level diagnostics (cyclomatic, cognitive,
  max-nesting, parameter count) as a `diagnose()` library that the
  forthcoming analyzer-plugin entrypoint will call. Heavy metrics
  remain CLI-only.
- `lib/dartrics.dart` now exports the function-level metric calculator
  classes alongside the existing report shapes; this is the supported
  surface for `dartrics_lint` and any other embedder.

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
