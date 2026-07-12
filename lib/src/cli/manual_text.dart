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

> **For commands and prompts, start with [`dartrics ai-loop`](ai-loop.md).** That walkthrough is the operational playbook — shell commands, prompt examples, dismiss syntax. This manual is the conceptual reference: lens design, refactor / dismiss decision tree, full flag catalogue, and the snapshot / coverage / regression mechanics. Read the playbook to run the tool; come back here when you need to understand _why_ a lens fires.

> **Operator's manual for AI consumers.** README describes what `dartrics` _is_; this page describes what `dartrics` _does for you_ and how to drive it. If you are an AI editing Dart code with an editor-tool harness (Claude Code, Cursor, Codex, Aider, OpenHands), this is your reference.

## The premise — multiple lenses on your own writing

Humans read code and feel things. _"This function is gnarly."_ _"This class is doing too much."_ _"I can't tell what scope I'm in."_ These reactions are real signals about working-memory load, but they are not reproducible — different reviewers feel them at different thresholds, and an AI doesn't feel them at all.

Decades of software-engineering research has converted those felt reactions into reproducible measurements. Each metric in `dartrics` is one such **lens**: a specific, citation-backed instrument that surfaces a specific kind of "hard to read." None of the lenses is the whole picture. Putting on more than one lens, in succession, is the point.

Most of that catalogue — McCabe 1976, Halstead 1977, CK 1994, Hitz & Montazeri 1995, Cognitive Complexity 2017 — never made it into the daily toolbox of working programmers. The cost of _calculating_ the number, _interpreting_ it, and _acting on it_ was each individually expensive for a human reviewer. An AI loop absorbs all three. You compute in a second; the rationale and refactor moves are attached to the violation; the edit is yours to apply. The lenses that the literature catalogued for human reviewers are reachable to you in a way they weren't before.

`dartrics` does not gate. It surfaces. Its core value is letting you, the AI, run the same battery of lenses a careful human reviewer would, then **decide** — refactor, accept, dismiss with a reason, or punt to the operator. That decision step is first-class.

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
       ┌──────┬────────┼────────┬──────┐
       ▼      ▼        ▼        ▼
  REFACTOR DISMISS    PUNT    ACCEPT
  (lens    (load-     (need    (borderline
   shows    bearing    project  value on
   real     structure; context  healthy
   fix)     tracked    the      code; no
            reason)    harness  edit, no
                       lacks)   dismiss)
                       │
                       ▼
       ┌──────────────────────────────┐
       │  verify the lens moved       │  ← dartrics regression --reporter ai
       │  (REFACTOR / DISMISS only —  │
       │   PUNT awaits operator;      │
       │   ACCEPT loops to next)      │
       └──────────────────────────────┘
```

## The lens battery

For the full audit trail — selection principles, deviations from the cited definitions, off-by-default rationale, and the lenses deliberately not implemented — see [`doc/calibration.md`](calibration.md).

Each entry below names: **the felt reaction** it captures, **what the lens computes**, the **default warning threshold**, and **when to refactor vs. dismiss**.

### Function / method lenses

| Lens                    | "Hard to read" feeling                                      | What it measures                                                                                                                                            | Default warning |
| ----------------------- | ----------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------- |
| `cyclomatic-complexity` | "I'd have to trace too many paths to know this is correct." | `1 + d` decision points: `if`, `for`, `while`, `do`, `switch case`, `&&`, `||`, `?:`, `catch`. (McCabe 1976)                                                | 10              |
| `cognitive-complexity`  | "It's not just branchy, it's _tangled_."                    | Sonar's B1 (control flow) + B2 (nesting penalty) + B3 (logical-op sequences). Penalises nested branches more than sequential ones. (SonarSource 2017, rev.) | 15              |
| `number-of-parameters`  | "Too many knobs at the call site to remember by position."  | Number of _positional_ parameters (required + optional positional). (Fowler 1999)                                                                           | 4               |
| `source-lines-of-code`  | "I have to scroll."                                         | Non-blank, non-comment-only body lines.                                                                                                                     | —               |
| `method-length` (off)   | "This body owns more than one idea."                        | Total source lines spanned by the body, comments included.                                                                                                  | opt-in          |
| `halstead-volume` (off) | —                                                           | `N · log₂(η)`. Token-based program "size". (Halstead 1977)                                                                                                  | opt-in          |

### Class lenses

| Lens                         | "Hard to read" feeling                                    | What it measures                                                                                                                                                                                                                                                                             | Reference                                    |
| ---------------------------- | --------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| `number-of-methods`          | "Too many entry points to keep in my head."               | Members with non-empty bodies. Equivalent to WMC with uniform weight=1.                                                                                                                                                                                                                      | Lorenz & Kidd 1994; CK 1994                  |
| `weighted-methods-per-class` | "The whole class is heavy, not just one method."          | Sum of cyclomatic complexity across methods.                                                                                                                                                                                                                                                 | CK 1994                                      |
| `lcom4`                      | "This class is doing more than one thing."                | Connected components in the field-share + method-call graph. Only declared methods are in the graph — mixin-applied methods don't count, so a class whose methods cohere via a mixin can show LCOM4 ≥ 2. (Hitz & Montazeri 1995)                                                             | Hitz & Montazeri 1995                        |
| `coupling-between-objects`   | "This class needs to know about the world to do its job." | Distinct other types referenced anywhere in the class.                                                                                                                                                                                                                                       | CK 1994                                      |
| `response-for-class`         | "Touching one method drags too many friends along."       | `|methods ∪ method-names invoked from those methods|`. Invoked-method set is name-matched on `MethodInvocation` + constructor calls; extension tear-offs, callable-object `()` invocations, and `super.x` are intentionally not counted (the metric under-reports rather than over-reports). | CK 1994                                      |
| `class-length`               | "I can't see the class on one screen."                    | Total source lines spanned by the class. "Large class" code smell (Beck / Fowler); threshold side via the "Rule of 30" (Lippert & Roock).                                                                                                                                                    | Beck 1996; Fowler 1999; Lippert & Roock 2006 |

DIT (Depth of Inheritance Tree) and NOC (Number of Children) from CK are intentionally **not** provided. Dart's mixin + composition-over-inheritance culture keeps single-inheritance chains shallow, so they rarely produce signal.

### Library / file lenses (Martin 1994)

All three are polarity `neutral` (no default warning) and rank change-impact rather than fire as Pain/Uselessness verdicts; see [`doc/calibration.md`](calibration.md)'s "Per-file Martin granularity" for why.

| Lens                     | "Hard to read" feeling                   | What it measures                                                         |
| ------------------------ | ---------------------------------------- | ------------------------------------------------------------------------ |
| `efferent-coupling` (Ce) | "This file pulls on a lot of strings."   | Distinct project-internal + `package:` dependencies (excludes `dart:*`). |
| `afferent-coupling` (Ca) | "Touching this file ripples everywhere." | Incoming internal-import edges.                                          |
| `instability` (I)        | "This is a fragile hub."                 | `Ce / (Ca + Ce)`. 0 = maximally stable, 1 = maximally unstable.          |

## Signals — reference information, not verdicts

Alongside the lens battery, `dartrics analyze` emits a `signals:` block: per-declaration **fan-in** (`callers`, `calls`) and **fan-out** (`callees`, `calls`) computed off the same element-resolved reachability pass that powers `dartrics unused`. Signals are **not thresholded** — they carry no `severity`, no `threshold`, no warning. A high fan-in is not a violation; a fan-in of zero is not automatically a delete candidate (`unused` is the verdict for that). The framing is deliberate: signals answer *"what does the graph look like here?"* so you can compare it against intent. The lens battery answers *"did this scope cross a citation-backed threshold?"*.

How to read a signal:

| Signal                | What it tells you                                                                                                                                                                                                                                                                                                                            |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `fanInCallers` = 0    | Nobody invokes this declaration. Could be leftover code (delete candidate) **or** an unwired implementation that was supposed to be called from somewhere but the wiring never landed. The `unused` block is verdict-grade; the `fanInCallers = 0` framing on `signals` is the version that asks the loop to confirm against intent first.   |
| High `fanInCallers`   | The declaration is a hub. Refactoring it ripples; check `coverage` before deciding the risk is acceptable.                                                                                                                                                                                                                                   |
| High `fanOutCallees`  | The declaration coordinates many other types — overlaps in spirit with `response-for-class`, but at the declaration level and across files. A natural place to look when CC / Cognitive flagged the same scope.                                                                                                                              |
| `calls` ≫ `callees`   | Same callee invoked repeatedly. Often legitimate (loop body, retries); occasionally a sign that a helper should absorb the repetition.                                                                                                                                                                                                       |

Signals reach the AI / JSON reporters in full and the MD reporter as a top-10 reference table; SARIF and console don't carry them (no surface to render reference-only data without confusing them for findings). The JSON shape lives in `schemas/dartrics-report.schema.json` under `$defs.CallGraphSignal`.

### Drilling in — `dartrics inspect <symbol>`

When the `signals:` block surfaces something interesting but the surrounding neighbourhood is what you actually need to see, use:

```bash
dartrics inspect <symbol> [--depth N] [--direction up|down|both]
```

`<symbol>` matches by declared name. Homonym methods on different classes (`A.work`, `B.work`) stay disambiguated as separate `matches:` entries; pass `A.work` to narrow. The walker BFSs the resolved call graph from each matched anchor: `--direction up` returns the upstream callers, `--direction down` returns the downstream callees, `--direction both` (default) returns the union. `--depth` caps the number of edges from the anchor (default 2). Output is `--reporter ai` (token-shaped YAML, default) or `--reporter json` — there is no `md` or `sarif` form because `inspect` is itself a reference-only probe, not a finding list.

Typical entry points:

* **Disambiguating `unused`** — `dartrics unused` flags `Foo.helper`. Before deleting, run `dartrics inspect Foo.helper --direction up --depth 3` and confirm the graph really has no inbound edge. If the unused detector saw it correctly, the upstream block is empty; if it didn't, the missing wiring shows up in the matches.
* **Sizing a refactor blast radius** — CC or Cognitive flagged `Parser.parse`. Run `dartrics inspect Parser.parse --direction up --depth 2` to see which call sites would have to follow if you change the signature.
* **Tracing what a coordinator owns** — high `fanOutCallees` on `Service.handleRequest`. Run `dartrics inspect Service.handleRequest --direction down --depth 2` to see the immediate downstream surface before you decide whether `response-for-class` is over-firing or correctly firing.

`inspect` does not gate, does not classify, and is **not** part of the refactor / dismiss / punt decision — it feeds that decision with structure that the lens output alone doesn't carry.

## Polarity — which way is healthier

Each lens declares a `polarity`:

* `down` — lower is better. The default. (CC, Cognitive, params, SLOC, length, NOM, WMC, LCOM4, CBO, RFC.)
* `neutral` — neither direction is universally good; the regression diff still surfaces deltas but doesn't classify them. (Halstead Volume; Ce, Ca, instability — the per-file Martin lenses are change-impact rankings, not Pain/Uselessness verdicts. See "Per-file Martin granularity" in [`doc/calibration.md`](calibration.md).)

You read this off the regression diff so you don't accidentally celebrate a metric that drifted the wrong way.

## The accept / refactor / dismiss decision

This is the step that distinguishes `dartrics` from a linter. For every violation the report shows you:

### Refactor when…

The metric points at a real readability problem and the structure is **decomposable without loss of intent**. Standard moves:

| Lens                       | First moves to try                                                                                                                                                                                                                               |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `cyclomatic-complexity`    | Extract Method · Replace Conditional with Polymorphism · Guard Clauses · Replace nested ternary with named branches                                                                                                                              |
| `cognitive-complexity`     | Extract the deepest branch · Replace `if/else if` chain with typed dispatch · Collapse boolean spaghetti via early returns                                                                                                                       |
| `number-of-parameters`     | Promote positional parameters to named (`foo({required T a, …})`) — the call site reads as `foo(a: …)` and the metric drops to zero · Group related positional parameters into a record · Move method onto the type that owns most of the inputs |
| `method-length`            | Extract Method along the comment seams · Move bookkeeping to a helper                                                                                                                                                                            |
| `lcom4`                    | Split the class along the connected components. The components are usually two responsibilities pretending to be one.                                                                                                                            |
| `coupling-between-objects` | Hide concrete types behind an interface · Move the orchestration to a coordinator class                                                                                                                                                          |
| `response-for-class`       | Move methods that only call out to other types onto those types · Apply Tell-Don't-Ask                                                                                                                                                           |
| `instability`              | Move stable types upward, depend on abstractions · Move volatile types into leaves                                                                                                                                                               |

`dartrics rules --reporter ai` dumps the full per-metric `refactorHints` — keep that catalogue at hand or rely on auto-explain to inline it per run.

### Accept when…

The lens fired, you read the code end-to-end, and a careful human reviewer would also leave it alone — typically a value at or barely over threshold on code that reads fine. **Accept = no edit, no `// dartrics:dismiss`, no punt. Move to the next violation.**

Accept is a distinct outcome from dismiss. Dismiss commits a tracked `reason="…"` because the structure is load-bearing and future readers need to see why the metric will keep firing on this scope. Accept is for cases where there is no recurring story to track — the next refactor in the area may legitimately drop the value under threshold, or the value may already be low enough that the warning is more of a heads-up than a finding. Adding a dismiss comment here pollutes the source with a tool annotation that does not function.

When the same kind of violation accepts repeatedly across many sites on the same idiom, that is the **threshold-calibration** signal (see the calibration note below): adjust `dartrics: { metrics: { <id>: { warning: <n> } } }` once instead of accepting N times across the project.

### Before you dismiss — engage, don't escape

The most common failure mode in this loop is **dismiss-as-escape**: silencing a violation not because the structure is genuinely load-bearing but because the refactor looks hard enough that dismiss becomes the productive-feeling next move. The signal that you are doing this is the _shape of your dismiss reason itself_ — phrases like "the metric is technically right but…", "the threshold is too tight for this idiom", or "splitting wouldn't really help here" are not load-bearing reasons; they are exit phrases.

Three checks before you reach for dismiss:

1. **Have you read the function end-to-end?** Every branch, every condition, every nested helper. If you've only read the signature and the metric value, the dismiss is premature.
2. **Have you tried a specific refactor and rejected it on a concrete structural reason?** "I didn't try" is not a reason. "I tried Extract Method on the deepest branch; the helper became a one-line passthrough that hid the per-case structure the reader needs to see" is a reason. The second sentence names a specific move and what its specific failure was.
3. **Would a careful human reviewer agree the structure is load-bearing?** If you suspect a reviewer would refactor, so should you.

Dismiss commits a `reason="…"` that future readers (human and AI) will rely on. Use it when it earns its weight. When you genuinely don't know, **punt** to the operator (the PUNT branch in the loop diagram above) instead of suppressing the signal — punt is cheap and recoverable, dismiss is sticky.

There is one path that looks like dismiss but isn't: **threshold calibration**. When the same kind of violation fires across many sites on the same Dart idiom, the threshold may be wrong for the codebase, not the code. The right move there is `dartrics: { metrics: { <id>: { warning: <n> } } }` in `analysis_options.yaml` — one tracked, operator-audited decision instead of N parallel dismiss entries. Reach for calibration when the same dismiss reason would otherwise repeat 5+ times across the project.

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

The lens reads it but you genuinely don't know whether the structure is load-bearing without project context the harness hasn't given you (domain rules, performance constraints, historical bug fixes baked into a function shape).

Punt has no in-tree syntax — no comment directive, no YAML key, no field in the JSON report. It is deliberately a natural-language channel between you and the operator, not a tracked artifact. `dartrics` is a tool _for both AI and human_, and the lens values that anchor your decision don't carry equivalent meaning to the operator the way they do to you; surfacing a `cognitive-complexity: 22` number doesn't transfer the situation. Translate what you saw into the project's own vocabulary, name the load-bearing hypothesis you cannot confirm, and ask in the same channel the harness uses to reach the human (chat, PR comment, whatever fits). When the answer comes back, route it into refactor or dismiss on the next pass.

## Default relaxations — Flutter and test files

Two ergonomics defaults are on out of the box so AI loops don't waste cycles refactoring code shapes that are legitimately load-bearing:

* **`flutter: true`** (default). On a class that directly extends a known widget superclass (`StatelessWidget`, `StatefulWidget`, `State`, `ConsumerWidget`, `ConsumerStatefulWidget`, `HookWidget`, `HookConsumerWidget`), the **constructor** skips `number-of-parameters` because `key:` plus a long callback list is the cultural norm. `Widget.build()` is **measured normally**. Non-Flutter packages are unaffected because no class matches.
* **`test: true`** (default). On files under `test/` or `integration_test/` whose basename ends in `_test.dart`: function-level `method-length` / `source-lines-of-code` step aside (AAA blocks are normal); class-level `class-length` / `number-of-methods` step aside (test classes legitimately hold many `@Test` methods); cognitive complexity applies a test-DSL discount — closures passed as invocation arguments (`group()` / `test()` registration callbacks) don't accrue to the enclosing function, so a declarative test `main()` doesn't fire the lens while a branchy named helper still does. Helpers like `test/helpers.dart` stay under strict thresholds because they're imported by tests rather than being tests.

Both default to on because the failure mode of "the lens fires on a healthy Flutter widget / test method" is far more common than the failure mode of "the lens didn't fire when it should have." Flip either to `false` in `analysis_options.yaml` if you want the strict thresholds applied uniformly.

## High-coverage signal — `complexityJustified`

If `--coverage <path>` is engaged (auto-detected from `coverage/lcov.info`) the report annotates each violation with `coverage` (line) and `branchCoverage` when the lcov has `BRDA:` records. CC and Cognitive violations whose scope is well-tested (branch ≥ 0.8, or line ≥ 0.95 when no branch data) get `complexityJustified: true`.

When the flag fires, two sibling fields surface the engine's decision so you don't have to re-derive it: `complexityJustifiedBy` is `branch` or `line` (whichever rule won), and `complexityJustifiedThreshold` is the literal cutoff that rule used (`0.8` or `0.95`). Both fields are absent when `complexityJustified` is false. Reporters pass the trio through verbatim — JSON, AI / YAML, MD, SARIF.

**Read this as: "the human has already paid the price of branching with tests; refactor at your own risk."** AI loops should generally leave `complexityJustified` violations alone unless the metric is _catastrophically_ over threshold (e.g. CC > 2× warning).

The AI reporter sorts these to the bottom so they don't compete for token budget.

## The cosmetic-split anti-pattern

Common AI failure mode: split a 30-line function with CC = 14 into ten three-line helpers. CC drops to 4 in the original, but each helper is now a one-line passthrough and the total readability got worse, not better.

`dartrics regression` surfaces this in the `cosmetic:` block. The block is **a narrow optional signal — parallel to the `signals:` block in `analyze` — not a verdict on the refactor.** The detector matches one specific signature:

```
tinyHelpersAdded ≥ 3 ∧ slocDelta > 4·helpers ∧ ccReduction < 2·helpers
```

`cosmeticSplitDetected: true` is load-bearing — **revert your refactor**. Real complexity reduction either:

* removes a dimension (boolean → enum, dispatch table → polymorphism), or
* consolidates duplicated branches into one parameterised path.

It does not redistribute branches across more functions while keeping all the branching logic.

`cosmeticSplitDetected: false` is **not a passing grade**. The detector is strong-positive / weak-negative — `false` only means this specific signature did not match. Mid-size helpers (body > `smallBodyThreshold`, default 3 SLOC), one-off cosmetic extractions, and refactors that average a real CC drop together with cosmetic helpers all return `false`. The reporters carry a `# narrow heuristic, not a global verdict` reminder alongside the boolean for this reason. Always cross-check `false` with a metric-free self-review of the diff before treating the refactor as accepted.

## The operational protocol

For an end-to-end walkthrough with prompt examples, see [`doc/ai-loop.md`](ai-loop.md). The structured reference:

| Step         | Command                                                                                                                                                                                          | Notes                                                                                                                                                              |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1. Setup     | populate `dartrics:` in `analysis_options.yaml`; generate `coverage/lcov.info`                                                                                                                   | `# yaml-language-server: $schema=…` enables IDE autocomplete; `flutter test --coverage` or `dart pub run coverage:test_with_coverage` powers `complexityJustified` |
| 2. Read      | `dartrics analyze --reporter ai --since origin/main --limit 30`                                                                                                                                  | `--since` filters violations to the scopes the diff touched; `--limit` caps tokens per section; auto-explain is always on                                                                               |
| 3. Decide    | refactor / dismiss / punt per violation                                                                                                                                                          | See [The accept / refactor / dismiss decision](#the-accept--refactor--dismiss-decision)                                                                            |
| 4. Apply     | edit code, add `// dartrics:dismiss <metric> reason="…"`, or — if you punted — raise the question to the operator in natural language (no in-tree syntax for punt; see [Punt when…](#punt-when)) | `--strict-dismiss` is an audit flag, not a refactor outcome                                                                                                        |
| 5. Verify    | `dartrics regression --before HEAD~1 --after HEAD --reporter ai`                                                                                                                                 | Look for `direction: improved`. `cosmeticSplitDetected: true` means revert; `false` is a narrow signal, not a passing grade. If you re-run `analyze` to verify a fix on the same file, pass `--snapshot none` — the cache rewrites itself every run, so two consecutive runs always report `changedFiles: 0` |
| 6. Pre-merge | `dartrics analyze --strict-dismiss --fatal-warnings`                                                                                                                                             | Ignores dismissals; exits non-zero on any remaining warning                                                                                                        |

The same `id` (16 hex chars) reappearing across runs means the previous fix didn't drop the metric. Refactor harder, or formalise as dismiss with a load-bearing reason — there is no third option of "ignore it again."

## Reporters — pick by audience

All four reporters render the same `AnalysisReport`. Pick by *who reads the output*, not by who runs the command — there is no "primary" reporter and the others are not derived from it.

| Reporter | Audience | Shape |
| --- | --- | --- |
| `--reporter ai` | You — the AI agent in this loop | Token-shaped: `counts:` section totals up front, auto-explain inlined, priority-sorted, `complexityJustified` sunk to the bottom |
| `--reporter md` | A human reviewer reading the report directly | Markdown sections, rationale + refactor-hint blocks per violated metric, suitable for paste-into-PR |
| `--reporter json` | `jq`, Python, CI gates, programmatic punt-list extraction | Schema-stable; validates against `schemas/dartrics-report.schema.json` |
| `--reporter sarif` | IDE / CI annotation surfaces | SARIF 2.1.0 |

The reporters are **parallel projections** of the same source data, not stages of a pipeline. The metric IDs (16-hex), exact threshold values, and `complexityJustified` sibling fields are bytes the renderers carry verbatim across all four, so a result you read out of `ai` matches the bytes the other three would emit for the same run.

If you have read `--reporter ai` and the destination is now a human or a CI sink, **re-run dartrics with the appropriate reporter flag.** Do not transcribe the ai output by hand: a reconstructed-from-memory copy drifts from the renderer's bytes, undoes the cross-reporter stability `dartrics` is designed to give you, and turns a verbatim-carried metric id into a stable-looking but unstable hex string.

## Flag map (for reference)

| Goal                                  | Flag                           | Notes                                                                                                                                                                                                                                             |
| ------------------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Pick the AI-shaped report             | `--reporter ai`                | Mandatory for AI loops                                                                                                                                                                                                                            |
| Filter to changed code                | `--since <git-ref>`            | Violations are scope-granular (diff hunks ∩ scope span); unused / signals are file-granular. Renames surface as the new path                                                                                                                      |
| Filter to changed bytes (no git)      | `--snapshot cache`             | Default; per-file sha256                                                                                                                                                                                                                          |
| Cap output for token budget           | `--limit <n>`                  | Applied per section (violations / unused / signals) after priority sort                                                                                                                                                                           |
| Skip dismissals (audit)               | `--strict-dismiss`             | Exposes the raw triage list                                                                                                                                                                                                                       |
| Speed up resolution                   | `--concurrency <n>`            | Defaults to host CPU count, clamped to 16                                                                                                                                                                                                         |
| Block on warnings                     | `--fatal-warnings`             | Combine with `--strict-dismiss` for CI                                                                                                                                                                                                            |
| Inject metric catalogue once          | `dartrics rules --reporter ai` | Feed once into a system prompt                                                                                                                                                                                                                    |
| Verify a refactor                     | `dartrics regression`          | Runs `git worktree` for the historical side. `--metric <id>` (repeatable) restricts the diff to the named lenses                                                                                                                                  |
| Audit your config                     | `dartrics doctor`              | Flags unknown config keys (with did-you-mean hints), unknown metric ids, and threshold mis-ordering. Read-only                                                                                                                                                                                    |
| Delete unused public-API declarations | `dartrics unused --apply`      | In-place deletion of unused top-level functions / classes / typedefs / extensions. Refuses on a dirty git tree (override `--force`). `test/` excluded by default (override `--include-tests`). Run `dart fix --apply` afterwards to clean imports |
| Walk the call graph around a symbol   | `dartrics inspect <symbol>`    | Reference-only probe (no thresholds, no severity). `--depth N` (default 2), `--direction up\|down\|both` (default `both`). Reporters: `ai` (default), `json`. See [Signals — reference information, not verdicts](#signals--reference-information-not-verdicts) |

## Exit codes

| Code | Meaning                                        | What you do                                                                                                                                           |
| ---- | ---------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0    | Clean                                          | Continue.                                                                                                                                             |
| 1    | Violations + `--fatal-warnings`                | Either refactor or dismiss with reason.                                                                                                               |
| 64   | Bad CLI args                                   | Re-read your command.                                                                                                                                 |
| 65   | Bad input (e.g. `--since` ref doesn't resolve) | Surface to the user; don't guess a different ref.                                                                                                     |
| 70   | Internal error                                 | Surface to the user with the stderr message; this is a bug in `dartrics`.                                                                             |
| 78   | Bad config                                     | The stderr message names the offending key. The config schema (`schemas/dartrics-config.schema.json`) catches most of these in-editor before you run. |

## What's _not_ in the lens battery

Knowing what `dartrics` deliberately doesn't measure is part of the contract:

* **No "code smell" detectors.** No god-object, no feature-envy, no shotgun-surgery heuristics. Those land in noise territory at the false-positive rates `analyzer` can support.
* **No automatic fixes.** `dartrics` measures and explains. It does not edit your code. The dismiss channel is _you_ writing a comment / YAML, not the tool rewriting the source.
* **No ML-derived weights.** Every threshold is documented and overridable. Lens output is reproducible across runs given the same source tree.
* **No cross-PR memory.** The tool doesn't remember "this dismiss was rejected last iteration." Stay session-local.
* **No test-quality lenses.** Coverage is read in only as a complexity-justification signal. Mutation score, assertion density, etc. are out of scope.

## Pointers

* README — project overview and install.
* AGENTS.md — contributor / PR conventions.
* `doc/ai-loop.md` — narrative walkthrough of one full iteration with sample prompts.
* `dartrics rules --reporter ai` — full rationale + refactor-hint catalogue at runtime.
* `schemas/dartrics-config.schema.json` — IDE autocomplete + typo detection for the config block.
* `schemas/dartrics-report.schema.json` — JSON-reporter output schema (use this if you parse the report yourself).
* `schemas/dartrics-dismissals.schema.json` — sidecar schema for the YAML dismiss form.
''';
