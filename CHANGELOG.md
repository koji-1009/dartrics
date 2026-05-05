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
