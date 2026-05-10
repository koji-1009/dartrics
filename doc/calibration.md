# Calibration

dartrics' lens battery is anchored to published sources. This page is the audit trail for that anchoring: what's selected and why, and where the implementation departs from the source's literal definition.

Threshold *numbers* (e.g. CC warn 10, CBO warn 14) follow the cited sources unchanged. What can differ is *what is counted* — those deviations are listed below with their justification.

## Selection principles

- **Each lens cites a published source.** Lenses without one are excluded.
- **One lens, one signal.** Lenses that derive purely from already-shipped lenses add no orthogonal signal and are excluded.
- **Idiom-misaligned lenses are excluded.** Metrics whose source assumptions don't hold for Dart (e.g. inheritance-depth metrics on a mixin + composition language) are excluded.
- **Off-by-default when overlap or assumption-misfit is structural.** Halstead Volume and Method Length overlap with simpler shipped lenses; Martin's Abstractness and Distance assume "package = release unit", which Dart's 1-file-1-library granularity breaks.

## Selected lenses

| Lens | Source |
| --- | --- |
| `cyclomatic-complexity` | McCabe 1976 |
| `cognitive-complexity` | Campbell / SonarSource white paper, 2017 (rev.) — *industry source, not peer-reviewed* |
| `number-of-parameters` | Fowler 1999 |
| `source-lines-of-code` | Boehm 1981 |
| `method-length` *(off)* | Beck 1996 |
| `halstead-volume` *(off)* | Halstead 1977 |
| `number-of-methods` | Lorenz & Kidd 1994; Chidamber & Kemerer 1994 |
| `weighted-methods-per-class` | Chidamber & Kemerer 1994 |
| `lcom4` | Hitz & Montazeri 1995 |
| `cbo` | Chidamber & Kemerer 1994 |
| `rfc` | Chidamber & Kemerer 1994 |
| `class-length` | Beck 1996; Fowler 1999; Lippert & Roock 2006 |
| `efferent-coupling` / `afferent-coupling` / `instability` | Martin 1994 |
| `abstractness` *(off)* / `distance-from-main-sequence` *(off)* | Martin 1994 |

Default thresholds and per-lens descriptions live in `README.md` ("Provided metrics") and `doc/manual.md` ("The lens battery"). Full bibliographic citations are exposed by each lens's `references` getter and surface through `dartrics rules`.

## Counting-rule deviations

These deviate from the source's literal definition; the threshold numbers are unchanged.

### `cyclomatic-complexity` — sealed-aware

McCabe 1976 counts every `switch` case arm in `d`. dartrics excludes case arms when the subject is a `sealed` class, because Dart 3.0+ enforces exhaustiveness at compile time — the "did I forget a case" reading load that case arms otherwise impose isn't there. Code: `lib/src/metrics/function/cyclomatic_complexity.dart`.

### `number-of-parameters` — positional only

Fowler 1999 flags long parameter lists. dartrics counts only positional parameters; named parameters are weight-zero. Fowler's smell targets *positional-recall load* at the call site (`foo(true, false, 3)` — what does each slot mean?). Dart's `foo(animated: false, retries: 3)` carries each name on the spot. Code: `lib/src/metrics/function/number_of_parameters.dart`.

### `lcom4` — declared methods only

Hitz & Montazeri 1995 take connected components over methods that share a field or call each other. dartrics excludes methods inherited via mixin application — counting them as "members of this class" produces systematic false positives in mixin-heavy Dart code. The trade-off is explicit: a class whose only cohesion comes from a shared mixin will show LCOM4 ≥ 2. Code: `lib/src/metrics/class/lcom4.dart`.

## Off-by-default lenses

| Lens | Reason for off-by-default |
| --- | --- |
| `halstead-volume` | Strong correlation with CC and SLOC (Alfadel et al. 2017); emitting all three duplicates signal. |
| `method-length` | By definition `SLOC + blanks + comment-only lines`. SLOC alone carries the same signal plus a known offset. |
| `abstractness` / `distance-from-main-sequence` | Martin's framing assumes "package = release unit"; Dart's 1-file-1-library granularity makes per-file values brittle. Off until directory-level aggregation lands. |
