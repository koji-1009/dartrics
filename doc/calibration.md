# Calibration

dartrics' lens battery is anchored to published sources. This page is the audit trail for that anchoring: what's selected and why, and where the implementation departs from the source's literal definition.

Threshold *numbers* (e.g. CC warn 10) follow the cited sources unchanged. What can differ is *what is counted* — those deviations are listed below with their justification.

## Selection principles

- **Each lens cites a published source.** Lenses without one are excluded.
- **One lens, one signal.** Lenses that derive purely from already-shipped lenses add no orthogonal signal and are excluded.
- **Idiom-misaligned lenses are excluded.** Metrics whose source assumptions don't hold for Dart (e.g. inheritance-depth metrics on a mixin + composition language) are excluded.
- **Off-by-default when overlap is structural.** Halstead Volume and Method Length overlap with simpler shipped lenses (CC / SLOC), so they ship disabled.
- **Informational polarity for per-file Martin lenses.** `efferent-coupling`, `afferent-coupling`, and `instability` ship with `polarity: neutral` because per-file granularity (a Dart library is one file; the release unit is the pub package) breaks Martin's package-as-release-unit framing. The values still rank change-impact; see "Per-file Martin granularity" below.

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
| `coupling-between-objects` | Chidamber & Kemerer 1994 |
| `response-for-class` | Chidamber & Kemerer 1994 |
| `class-length` | Beck 1996; Fowler 1999; Lippert & Roock 2006 |
| `efferent-coupling` / `afferent-coupling` / `instability` | Martin 1994 |

Default thresholds and per-lens descriptions live in `README.md` ("Provided metrics") and `doc/manual.md` ("The lens battery"). Full bibliographic citations are exposed by each lens's `references` getter and surface through `dartrics rules`.

## Counting-rule deviations

These deviate from the source's literal definition; the threshold numbers are unchanged.

### `cyclomatic-complexity` — exhaustiveness-aware

McCabe 1976 counts every `switch` case arm in `d`. dartrics excludes case arms when the subject's static type is a `sealed` class or an `enum`, because Dart 3.0+ enforces exhaustiveness at compile time on both — the "did I forget a case" reading load that case arms otherwise impose isn't there. The discount applies to switch statements and switch expressions alike. On switch expressions, a bare `_ =>` wildcard arm (untyped, unguarded) is treated as the `default:` equivalent and is never counted; typed (`int _ =>`) or guarded (`_ when c =>`) wildcard arms still count. Code: `lib/src/metrics/function/cyclomatic_complexity.dart`.

### `cyclomatic-complexity` — null-coalescing operators counted

McCabe 1976 predates null-aware operators, so its construct list doesn't mention them. dartrics counts `??` and `??=` as one decision point each: `a ?? b` branches exactly like the counted ternary `a != null ? a : b`, and `a ??= b` is `a = a ?? b`. Leaving them at zero would let the same control flow score differently depending on spelling. Code: `lib/src/metrics/function/cyclomatic_complexity.dart`.

### `cognitive-complexity` — closure content appears in two records

Campbell's rules fold a lambda's control flow into the enclosing method's score (method-like structures increment the nesting level; their contents keep scoring). dartrics keeps that attribution *and* emits every closure as its own metric record (scope kind `closure`), so a branchy closure scores both in the enclosing function's cognitive value and, unnested, in its standalone record. The two readings answer different questions — "how hard is this function to read top-to-bottom" vs. "how hard is this callback on its own" — and local named functions have carried the same double reading since they became separate records. Cyclomatic complexity does not duplicate: closures are excluded from the enclosing function's CC and score only on their own record. Code: `lib/src/metrics/function/cognitive_complexity.dart`, `lib/src/metrics/metric_engine.dart`.

### `number-of-parameters` — positional only

Fowler 1999 flags long parameter lists. dartrics counts only positional parameters; named parameters are weight-zero. Fowler's smell targets *positional-recall load* at the call site (`foo(true, false, 3)` — what does each slot mean?). Dart's `foo(animated: false, retries: 3)` carries each name on the spot. Code: `lib/src/metrics/function/number_of_parameters.dart`.

### `lcom4` — declared methods only

Hitz & Montazeri 1995 take connected components over methods that share a field or call each other. dartrics excludes methods inherited via mixin application — counting them as "members of this class" produces systematic false positives in mixin-heavy Dart code. The trade-off is explicit: a class whose only cohesion comes from a shared mixin will show LCOM4 ≥ 2. Code: `lib/src/metrics/class/lcom4.dart`.

## Off-by-default lenses

| Lens | Reason for off-by-default |
| --- | --- |
| `halstead-volume` | Strong correlation with CC and SLOC (Alfadel et al. 2017); emitting all three duplicates signal. |
| `method-length` | By definition `SLOC + blanks + comment-only lines`. SLOC alone carries the same signal plus a known offset. |

## Per-file Martin granularity

Martin's 1994 framework was developed for OO languages where "package = release unit" and a file typically holds one main type (Java's `public class Foo` ↔ `Foo.java` is compiler-enforced). Dart does **not** have that constraint:

- A `.dart` file is a library; one library can hold any number of `class` / `mixin` / `extension` / top-level function declarations.
- The release unit in Dart is the *pub package*, not the file. There is no first-class concept of a named multi-file module between the file and the package.

`efferent-coupling` (per-file Ce), `afferent-coupling` (cross-file Ca), and `instability` (`I = Ce / (Ca + Ce)`) ship because the count itself is a useful change-impact ranking even when divorced from Martin's `A`-paired Pain/Uselessness verdicts. They are *not* Martin-frame "is this design good" gates; they are "if you change this file, who breaks?" rankings. Polarity is `neutral` for all three — no default warning fires, and the regression diff surfaces drift without classifying it as improved/regressed. Set a threshold via `dartrics: { metrics: { efferent-coupling: { warning: <n> } } }` to opt into a project-specific gate.
