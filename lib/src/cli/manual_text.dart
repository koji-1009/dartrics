// AUTO-MIRROR of doc/manual.md.
//
// `dartrics manual` prints this string verbatim. The mirror is enforced by
// `test/cli/manual_command_test.dart` which compares byte-for-byte against
// the markdown file at the repo root, so the two cannot drift.
//
// Why a const string and not a runtime file read: `dart pub global
// activate dartrics` does not preserve the package's `doc/` tree on the
// consumer's machine, so a file-based read would 404 outside the dev
// checkout. The manual must travel with the executable bytes.
//
// When you edit doc/manual.md, copy the new content into the raw
// triple-quoted literal below and run `dart test test/cli/manual_command_test.dart`
// to confirm parity. Conversely, if you change this string, update
// doc/manual.md to match.

/// Operator's manual printed by `dartrics manual`. Mirrors doc/manual.md.
const String manualText = r'''
# dartrics manual — for AI agents

> **Operator's manual for AI consumers.** README describes what `dartrics` *is*; this page describes what `dartrics` *does for you* and how to drive it. If you are an AI editing Dart code with an editor-tool harness (Claude Code, Cursor, Codex, Aider, OpenHands), this is your reference.

## The premise — multiple lenses on your own writing

Humans read code and feel things. *"This function is gnarly."* *"This class is doing too much."* *"I can't tell what scope I'm in."* These reactions are real signals about working-memory load, but they are not reproducible — different reviewers feel them at different thresholds, and an AI doesn't feel them at all.

Decades of software-engineering research has converted those felt reactions into reproducible measurements. Each metric in `dartrics` is one such **lens**: a specific, citation-backed instrument that surfaces a specific kind of "hard to read." None of the lenses is the whole picture. Putting on more than one lens, in succession, is the point.

Most of that catalogue — McCabe 1976, Halstead 1977, CK 1994, LCOM4 1995, Cognitive Complexity 2018 — never made it into the daily toolbox of working programmers. The cost of *calculating* the number, *interpreting* it, and *acting on it* was each individually expensive for a human reviewer. An AI loop absorbs all three. You compute in a second; the rationale and refactor moves are attached to the violation; the edit is yours to apply. The lenses that the literature catalogued for human reviewers are reachable to you in a way they weren't before.

`dartrics` does not gate. It surfaces. Its core value is letting you, the AI, run the same battery of lenses a careful human reviewer would, then **decide** — refactor, accept, or formally dismiss with a reason. That decision step is first-class.

```
                you propose code
                       │
                       ▼
       ┌──────────────────────────────┐
       │  put on the lenses           │  ← dartrics analyze --reporter ai
       │  (reproducible readability)  │
       └──────────────────────────────┘
                       │
              for each violation:
                       │
       ┌───────────────┼───────────────┐
       ▼               ▼               ▼
  REFACTOR         DISMISS         PUNT
  (lens shows      (lens reads     (mark unsure
   real fix)        it but the      and surface
                    structure is    a question)
                    load-bearing)
                       │
                       ▼
       ┌──────────────────────────────┐
       │  verify the lens moved       │  ← dartrics regression --reporter ai
       └──────────────────────────────┘
```

## The lens battery

These lenses ship default-off (everything else in the catalogue below is on by default):

- **Halstead Volume** — predictive value over cyclomatic complexity hasn't held up empirically; opt in if you want a token-weighted "size" reading
- **Method Length** — high correlation with SLOC in production code, so emitting both is redundant noise. Opt in when you specifically want screen-real-estate (counts blanks + comments) instead of pure code volume
- **Abstractness** / **Distance from Main Sequence** — Martin's framing assumes "package = release unit"; Dart's 1-file-1-library granularity makes the per-file values brittle until aggregation lands
- **Widget Tree Depth** — Flutter-specific; opt in for projects that want the deep-`Container(child: ...)` reading
- **Null-Aware Chain Depth** / **Async Chain Depth** — Dart-3-idiom signals; opt in when project conventions on "too deep" `?.` chains or nested `await` calls are settled enough to threshold

Halstead Difficulty / Effort and the Maintainability Index were dropped in 0.1.0: both are pure derivations of the underlying token counts and `CC + V + LOC` respectively — they add no orthogonal signal beyond what the underlying lenses already provide.

Each entry below names: **the felt reaction** it captures, **what the lens computes**, the **default warning threshold**, and **when to refactor vs. dismiss**.

### Function / method lenses

| Lens | "Hard to read" feeling | What it measures | Default warning |
| --- | --- | --- | --- |
| `cyclomatic-complexity` | "I'd have to trace too many paths to know this is correct." | `1 + d` decision points: `if`, `for`, `while`, `do`, `switch case`, `&&`, `\|\|`, `?:`, `catch`. (McCabe 1976) **Sealed-aware**: case arms of a switch whose subject is a sealed class don't count — exhaustiveness is compiler-enforced so the reader carries no "did I forget a case" cognitive load. | 10 |
| `cognitive-complexity` | "It's not just branchy, it's *tangled*." | Sonar's B1 (control flow) + B2 (nesting penalty) + B3 (logical-op sequences). Penalises nested branches more than sequential ones. (Sonar 2018) | 15 |
| `maximum-nesting-level` | "I can't tell which scope I'm in." | Max depth of `if`, `for`, `while`, `do`, `switch`, `try`, closure blocks. | 4 |
| `number-of-parameters` | "Too many knobs at the call site." | Positional + named + optional. | 4 |
| `boolean-trap` | "What does `foo(true, false, true)` even mean at the call site?" | Number of *positional* `bool`-typed parameters. Named bool parameters are intentionally not counted because Dart's named call-site `foo(animated: true)` carries the intent on the spot. (McConnell *Code Complete* 2004; Bloch *Effective Java* item 36) | 2 |
| `widget-tree-depth` (off) | "This Flutter `build()` is six `Container(child: ...)` chains deep." | Deepest chain of nested constructor calls in the body. Complement to `maximum-nesting-level`, which only counts control-flow constructs and gives 0 on a healthy declarative tree. | opt-in (7) |
| `null-aware-chain-depth` (off) | "I can't track `a?.b?.c?.d?.e` in my head." | Longest chain of `?.` operators in any expression. Each `?.` is an implicit non-null guard the reader holds in working memory; deep chains read as conditional dataflow. | opt-in (4) |
| `async-chain-depth` (off) | "What's resolving when in `await foo(await bar(await baz()))`?" | Deepest *nesting* of `await` expressions on any path. Sequential awaits don't count — only nested ones, where each inner await suspends on the result of an outer await. | opt-in (3) |
| `source-lines-of-code` | "I have to scroll." | Non-blank, non-comment-only body lines. | — |
| `method-length` (off) | "This body owns more than one idea." | Total source lines spanned by the body, comments included. | opt-in |
| `halstead-volume` (off) | — | `N · log₂(η)`. Token-based program "size". (Halstead 1977) | opt-in |

### Class lenses

| Lens | "Hard to read" feeling | What it measures | Reference |
| --- | --- | --- | --- |
| `number-of-methods` | "Too many entry points to keep in my head." | Members with non-empty bodies. | — |
| `weighted-methods-per-class` | "The whole class is heavy, not just one method." | Sum of cyclomatic complexity across methods. | CK 1994 |
| `lcom4` | "This class is doing more than one thing." | Connected components in the field-share + method-call graph. Only declared methods are in the graph — mixin-applied methods don't count, so a class whose methods cohere via a mixin can show LCOM4 ≥ 2. (Hitz & Montazeri 1995) | Hitz & Montazeri 1995 |
| `coupling-between-objects` | "This class needs to know about the world to do its job." | Distinct other types referenced anywhere in the class. | CK 1994 |
| `response-for-class` | "Touching one method drags too many friends along." | `\|methods ∪ method-names invoked from those methods\|`. Invoked-method set is name-matched on `MethodInvocation` + constructor calls; extension tear-offs, callable-object `()` invocations, and `super.x` are intentionally not counted (the metric under-reports rather than over-reports). | CK 1994 |
| `class-length` | "I can't see the class on one screen." | Total source lines spanned by the class. | — |

DIT (Depth of Inheritance Tree) and NOC (Number of Children) from CK are intentionally **not** provided. Dart's mixin + composition-over-inheritance culture keeps single-inheritance chains shallow, so they rarely produce signal.

### Library / file lenses (Martin 1994)

| Lens | "Hard to read" feeling | What it measures |
| --- | --- | --- |
| `efferent-coupling` (Ce) | "This file pulls on a lot of strings." | Distinct project-internal + `package:` dependencies (excludes `dart:*`). |
| `afferent-coupling` (Ca) | "Touching this file ripples everywhere." | Incoming internal-import edges. |
| `instability` (I) | "This is a fragile hub." | `Ce / (Ca + Ce)`. 0 = maximally stable, 1 = maximally unstable. |
| `abstractness` (A, off) | — | Abstract / mixin types ÷ total class-like declarations. Opt-in. |
| `distance-from-main-sequence` (D, off) | "It's a concrete file that everyone depends on, or an abstract leaf." | `\|A + I − 1\|`. Both extremes are smells. Opt-in (depends on `abstractness`). |

## Polarity — which way is healthier

Each lens declares a `polarity`:

- `down` — lower is better. The default. (CC, Cognitive, nesting, params, SLOC, length, NOM, WMC, LCOM4, CBO, RFC, Ce, Ca, instability, distance.)
- `up` — higher is better. No built-in metric uses this in 0.1.0; reserved for custom embedder metrics that want it.
- `neutral` — neither direction is universally good; the regression diff still surfaces deltas but doesn't classify them. (Halstead Volume, abstractness in isolation.)

You read this off the regression diff so you don't accidentally celebrate a metric that drifted the wrong way.

## The accept / refactor / dismiss decision

This is the step that distinguishes `dartrics` from a linter. For every violation the report shows you:

### Refactor when…

The metric points at a real readability problem and the structure is **decomposable without loss of intent**. Standard moves:

| Lens | First moves to try |
| --- | --- |
| `cyclomatic-complexity` | Extract Method · Replace Conditional with Polymorphism · Guard Clauses · Replace nested ternary with named branches |
| `cognitive-complexity` | Extract the deepest branch · Replace `if/else if` chain with typed dispatch · Collapse boolean spaghetti via early returns |
| `maximum-nesting-level` | Early return / continue · Extract inner block · Invert the condition to flatten the happy path |
| `number-of-parameters` | Introduce Parameter Object · Builder for optional config · Split into two functions if half the params are unused on each call |
| `boolean-trap` | Split into intent-named methods (`show()` / `hide()`) · Replace bool flags with a typed enum · Promote an "options" record so the call site reads as named fields |
| `method-length` | Extract Method along the comment seams · Move bookkeeping to a helper |
| `lcom4` | Split the class along the connected components. The components are usually two responsibilities pretending to be one. |
| `coupling-between-objects` | Hide concrete types behind an interface · Move the orchestration to a coordinator class |
| `response-for-class` | Move methods that only call out to other types onto those types · Apply Tell-Don't-Ask |
| `instability` / `distance-from-main-sequence` | Move stable types upward, depend on abstractions · Move volatile types into leaves |

`dartrics rules --reporter ai` dumps the full per-metric `refactorHints` — keep that catalogue at hand or rely on auto-explain to inline it per run.

### Dismiss when…

The lens reads it correctly but the structure is **load-bearing**: a state machine the user calls into; a recursive descent parser whose grammar mirrors the function shape; an exhaustive switch over a sealed type; a decoder fan-out where every branch is a real protocol case. Splitting it would hide intent, not clarify it.

A dismiss is a tracked, auditable decision, not a silent disable. You write:

```dart
// dartrics:dismiss cognitive-complexity reason="Recursive descent parser; splitting per-token would hide the grammar"
Token parse(Token start) { ... }
```

or, for projects that require author + timestamp:

```yaml
# dartrics-dismissals.yaml
version: 1
dismissals:
  - file: lib/parser.dart
    scope: Parser.parse
    metric: cognitive-complexity
    reason: "Recursive descent parser; splitting per-token would hide the grammar"
    by: claude-opus-4-7
    at: "2026-05-07T10:00:00Z"
```

The validator will reject reasons shorter than `minReasonLength` (default 20 chars) and stamp the violation with `dismissalRejected: <why>`. Your dismiss is **not silent**: if it didn't take, the next pass will tell you why.

Stale entries — dismissals that no longer match any live violation (scope renamed, function deleted, metric dropped below threshold) — appear in the report's `staleDismissals:` block, with a stderr WARNING per entry. Treat that as a cleanup candidate: the dismiss is doing nothing now, and leaving it in the file accumulates dead config. Files outside the analyzed set (filtered out by `--since` or snapshot) are not flagged as stale.

### Punt when…

The lens reads it but you genuinely don't know whether the structure is load-bearing without project context the harness hasn't given you (domain rules, performance constraints, historical bug fixes baked into a function shape). Surface a specific question to the user instead of guessing.

## Default relaxations — Flutter and test files

Two ergonomics defaults are on out of the box so AI loops don't waste cycles refactoring code shapes that are legitimately load-bearing:

- **`flutter: true`** (default). On a class that directly extends a known widget superclass (`StatelessWidget`, `StatefulWidget`, `State`, `ConsumerWidget`, `ConsumerStatefulWidget`, `HookWidget`, `HookConsumerWidget`), the **constructor** skips `number-of-parameters` because `key:` plus a long callback list is the cultural norm. `Widget.build()` is **measured normally** — `maximum-nesting-level` only counts control-flow constructs (`if`/`for`/`while`/`switch`/`try`/closure), so a healthy declarative tree gives 0 without special-casing. Visual depth from chained Widget literals belongs to the opt-in `widget-tree-depth` lens. Non-Flutter packages are unaffected because no class matches.
- **`test: true`** (default). On files under `test/` or `integration_test/` whose basename ends in `_test.dart`: function-level `method-length` / `source-lines-of-code` / `maximum-nesting-level` step aside (AAA blocks and nested `group`/`setUp`/`test` scaffolding are normal); class-level `class-length` / `number-of-methods` step aside (test classes legitimately hold many `@Test` methods). Helpers like `test/helpers.dart` stay under strict thresholds because they're imported by tests rather than being tests.

Both default to on because the failure mode of "the lens fires on a healthy Flutter widget / test method" is far more common than the failure mode of "the lens didn't fire when it should have." Flip either to `false` in `analysis_options.yaml` if you want the strict thresholds applied uniformly.

## High-coverage signal — `complexityJustified`

If `--coverage <path>` is engaged (auto-detected from `coverage/lcov.info`) the report annotates each violation with `coverage` (line) and `branchCoverage` when the lcov has `BRDA:` records. CC and Cognitive violations whose scope is well-tested (branch ≥ 0.8, or line ≥ 0.95 when no branch data) get `complexityJustified: true`.

When the flag fires, two sibling fields surface the engine's decision so you don't have to re-derive it: `complexityJustifiedBy` is `branch` or `line` (whichever rule won), and `complexityJustifiedThreshold` is the literal cutoff that rule used (`0.8` or `0.95`). Both fields are absent when `complexityJustified` is false. Reporters pass the trio through verbatim — JSON, AI / YAML, MD, SARIF, `dartrics explain`.

**Read this as: "the human has already paid the price of branching with tests; refactor at your own risk."** AI loops should generally leave `complexityJustified` violations alone unless the metric is *catastrophically* over threshold (e.g. CC > 2× warning).

The AI reporter sorts these to the bottom so they don't compete for token budget.

## The cosmetic-split anti-pattern

Common AI failure mode: split a 30-line function with CC = 14 into ten three-line helpers. CC drops to 4 in the original, but each helper is now a one-line passthrough and the total readability got worse, not better.

`dartrics regression` detects this:

```
tinyHelpersAdded ≥ 3 ∧ slocDelta > 4·helpers ∧ ccReduction < 2·helpers
```

When the regression diff prints `looksCosmetic: true`, **revert your refactor**. Real complexity reduction either:

- removes a dimension (boolean → enum, dispatch table → polymorphism), or
- consolidates duplicated branches into one parameterised path.

It does not redistribute branches across more functions while keeping all the branching logic.

## The operational protocol

Inside an AI loop, run this sequence. Each step has a clear contract.

### 1. Setup (once per session)

```yaml
# analysis_options.yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/koji-1009/dartrics/main/schemas/dartrics-config.schema.json

dartrics:
  # flutter: true and test: true are the defaults. Listed here for
  # discoverability — flip either to `false` to force the size-and-shape
  # lenses on widget code or test files respectively.
  metrics:
    cyclomatic-complexity: { warning: 10, error: 20 }
    cognitive-complexity:  { warning: 15, error: 25 }
    method-length:         { warning: 30, error: 60 }
    maximum-nesting-level: { warning: 4 }
    number-of-parameters:  { warning: 4, error: 8 }
  dismissals: {}                 # opt into the dismiss channel
  snapshot:
    mode: cache                  # `.dart_tool/dartrics/snapshot.json`
```

Generate coverage so `complexityJustified` works:

```bash
dart pub global activate coverage
dart pub run coverage:test_with_coverage
```

### 2. Read through the lenses

```bash
dartrics analyze \
  --reporter ai \
  --since origin/main \
  --limit 30
```

Why each flag matters in the loop:

| Flag | What it gives you |
| --- | --- |
| `--reporter ai` | YAML-ish output with `# dartrics ai-report v1` header. Sorted: severity ↓, then coverage ↓, then `complexityJustified` ↓, then `dismissed` ↓. The most actionable items are at the top. |
| `--since <ref>` | Only emit records whose owning file changed vs `<ref>`. Cross-file resolution still happens fully — only the *emitted* records are filtered. Stops you from re-litigating debt outside this PR. |
| `--limit <n>` | Hard cap on emitted entries after the priority sort. Excess is summarised in `truncated:`. Token-budget control. |
| (auto-explain) | Default-on. Every metric that fired gets its rationale + refactor hints attached as the report's `explain:` block. You don't need to know which metric ids exist. |
| `--coverage <path>` | Default-on when `coverage/lcov.info` exists. Adds `coverage` / `branchCoverage` / `complexityJustified` to each violation. |

### 3. For each violation, decide

Re-read [The accept / refactor / dismiss decision](#the-accept--refactor--dismiss-decision). The report's `id` field (16 hex chars, stable across runs) is your handle for "is this the same violation I tried to fix last iteration?"

### 4. Apply the change

Either edit the scope, or add a `// dartrics:dismiss` comment / a YAML sidecar entry. Don't reach for `--strict-dismiss` or remove the metric from config — those are operator escape hatches, not refactor outcomes.

### 5. Verify

Two complementary checks. Run both.

**Per-scope diff:**

```bash
dartrics regression --before HEAD~1 --after HEAD --reporter ai
```

You're looking for:

- `direction: improved` on the violations you targeted — your fix actually moved the metric.
- `looksCosmetic: false` on the summary — you didn't just shuffle complexity into helpers.
- No `direction: regressed` entries on metrics you didn't intend to touch.

**Strict triage list (CI / final review):**

```bash
dartrics analyze --strict-dismiss --fatal-warnings
```

`--strict-dismiss` ignores every dismissal so the operator sees the raw triage list. Combined with `--fatal-warnings`, this exits non-zero whenever an unsuppressed warning remains — suitable as a pre-merge gate.

### 6. If the same `id` reappears

Your fix didn't take. Open the corresponding scope, look at the metric value vs threshold delta in the new report, and either:

- refactor harder (the previous move was insufficient), or
- formalise the dismiss (you've concluded the structure is load-bearing).

There is no third option of "ignore it again."

## Flag map (for reference)

| Goal | Flag | Notes |
| --- | --- | --- |
| Pick the AI-shaped report | `--reporter ai` | Mandatory for AI loops |
| Filter to changed files | `--since <git-ref>` | Renames surface as the new path |
| Filter to changed bytes (no git) | `--snapshot cache` | Default; per-file sha256 |
| Cap output for token budget | `--limit <n>` | Applied after priority sort |
| Skip dismissals (audit) | `--strict-dismiss` | Exposes the raw triage list |
| Force rationale | `--explain <id>` | Repeatable; unions with auto-explain |
| Drop auto-explain | `--no-auto-explain` | Lean reports without rationale + refactor hints attached |
| Speed up resolution | `--concurrency <n>` | Defaults to host CPU count, clamped to 16 |
| Block on warnings | `--fatal-warnings` | Combine with `--strict-dismiss` for CI |
| Inject metric catalogue once | `dartrics rules --reporter ai` | Feed once into a system prompt |
| Verify a refactor | `dartrics regression` | Runs `git worktree` for the historical side |
| Audit your config | `dartrics doctor` | Flags unknown metric ids, unknown presets, threshold mis-ordering. Read-only |
| Reverse-lookup a violation | `dartrics explain <id>` | Pipe a JSON report in or use `--input <path>`. Returns rationale + refactor hints for one violation |
| Delete unused public-API declarations | `dartrics unused --apply` | In-place deletion of unused top-level functions / classes / typedefs / extensions. Refuses on a dirty git tree (override `--force`). `test/` excluded by default (override `--include-tests`). Run `dart fix --apply` afterwards to clean imports |

## Exit codes

| Code | Meaning | What you do |
| --- | --- | --- |
| 0 | Clean | Continue. |
| 1 | Violations + `--fatal-warnings` | Either refactor or dismiss with reason. |
| 64 | Bad CLI args | Re-read your command. |
| 65 | Bad input (e.g. `--since` ref doesn't resolve) | Surface to the user; don't guess a different ref. |
| 70 | Internal error | Surface to the user with the stderr message; this is a bug in `dartrics`. |
| 78 | Bad config | The stderr message names the offending key. The config schema (`schemas/dartrics-config.schema.json`) catches most of these in-editor before you run. |

## What's *not* in the lens battery

Knowing what `dartrics` deliberately doesn't measure is part of the contract:

- **No "code smell" detectors.** No god-object, no feature-envy, no shotgun-surgery heuristics. Those land in noise territory at the false-positive rates `analyzer` can support.
- **No automatic fixes.** `dartrics` measures and explains. It does not edit your code. The dismiss channel is *you* writing a comment / YAML, not the tool rewriting the source.
- **No ML-derived weights.** Every threshold is documented and overridable. Lens output is reproducible across runs given the same source tree.
- **No cross-PR memory.** The tool doesn't remember "this dismiss was rejected last iteration." Stay session-local.
- **No DIT / NOC.** Dart inheritance chains are too shallow for the metric to produce signal.
- **No test-quality lenses.** Coverage is read in only as a complexity-justification signal. Mutation score, assertion density, etc. are out of scope.

## Pointers

- README — project description, install, configuration reference.
- AGENTS.md — contributor / PR conventions.
- `doc/ai-loop.md` — narrative walkthrough of one full iteration with sample prompts.
- `dartrics rules --reporter ai` — full rationale + refactor-hint catalogue at runtime.
- `schemas/dartrics-config.schema.json` — IDE autocomplete + typo detection for the config block.
- `schemas/dartrics-report.schema.json` — JSON-reporter output schema (use this if you parse the report yourself).
- `schemas/dartrics-dismissals.schema.json` — sidecar schema for the YAML dismiss form.
''';
