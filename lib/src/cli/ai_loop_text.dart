// AUTO-MIRROR of doc/ai-loop.md.
//
// `dartrics ai-loop` prints this string verbatim. The mirror is enforced by
// `test/cli/ai_loop_command_test.dart` which compares byte-for-byte against
// the markdown file at the repo root, so the two cannot drift.
//
// Why a const string and not a runtime file read: `dart pub global
// activate dartrics` does not preserve the package's `doc/` tree on the
// consumer's machine, so a file-based read would 404 outside the dev
// checkout. The walkthrough must travel with the executable bytes.
//
// When you edit doc/ai-loop.md, copy the new content into the raw
// triple-quoted literal below and run `dart test test/cli/ai_loop_command_test.dart`
// to confirm parity. Conversely, if you change this string, update
// doc/ai-loop.md to match.

/// AI-loop walkthrough printed by `dartrics ai-loop`. Mirrors doc/ai-loop.md.
const String aiLoopText = r'''
# AI loop walkthrough

This guide shows how to plug `dartrics` into an AI-driven refactor loop. The flow is identical for Claude Code, Cursor, Codex, OpenHands, Aider, or any other agent that can shell out and read structured input — only the prompt-glue command differs.

The loop has four stations. dartrics is the lens at every station.

```
┌──────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│ 1. setup │ → │ 2. propose   │ → │ 3. apply     │ → │ 4. verify    │
└──────────┘   └──────────────┘   └──────────────┘   └──────────────┘
                ↑                                            │
                └────────────── iterate ─────────────────────┘
```

## 1. Setup (once per project)

Add a starter `dartrics:` block. The `# yaml-language-server` directive turns on IDE autocomplete from the published schema.

```yaml
# analysis_options.yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/koji-1009/dartrics/main/schemas/dartrics-config.schema.json

dartrics:
  flutter: true                 # only if you're shipping Flutter

  metrics:
    cyclomatic-complexity: { warning: 10, error: 20 }
    cognitive-complexity:  { warning: 15, error: 25 }
    method-length:         { warning: 30, error: 60 }
    number-of-parameters:  { warning: 4, error: 8 }

  dismissals: {}                # opt into the dismiss channel

  snapshot:
    mode: cache                 # gitignored at .dart_tool/dartrics/snapshot.json
```

Generate coverage if you want `complexityJustified` annotations. Pure Dart:

```bash
dart pub global activate coverage
dart pub run coverage:test_with_coverage
```

Flutter:

```bash
flutter test --coverage
```

Either writes `coverage/lcov.info`, which dartrics auto-discovers on the next analyze.

## 2. Propose (the agent reads dartrics)

Ask dartrics for a focused, AI-shaped report. Three flags carry most of the weight:

```bash
dartrics analyze \
  --reporter ai \
  --since origin/main \
  --limit 30
```

What each flag does for the AI:

| Flag | Why it matters |
| --- | --- |
| `--reporter ai` | Token-efficient YAML; sorted by severity → coverage → dismissed. The agent reads top-down and gets the most actionable items first. |
| `--since origin/main` | Only emit violations for the scopes the diff actually touched — untouched functions in a changed file stay out. Unused / signals stay file-granular because a change elsewhere in the file can legitimately flip them. Avoids re-litigating debt the agent isn't there to fix. |
| `--limit 30` | Per-section cap (violations, unused, and signals are each truncated independently) so a 1000-violation legacy codebase doesn't blow the context window. The truncated count is stamped into the report. |
| (auto-explain, always on) | Every metric that fired gets its rationale + refactorHints attached. The agent doesn't have to know which metrics exist. |

A typical AI-loop prompt:

```bash
dartrics analyze --reporter ai --since origin/main --limit 30 \
  | claude -p "Read the dartrics report. For each violation, choose one of:
  (a) FIX — refactor the scope so the metric drops below threshold,
  (b) DISMISS — add a // dartrics:dismiss <metric> reason=\"...\" comment
      directly above the declaration when the complexity is intentional,
  (c) ASK — surface a specific question if the right call isn't obvious.
  Use the rationale + refactorHints in the explain block to ground each fix.
  Each dismissal reason must be ≥20 chars and explain *why* the structure is
  load-bearing — not just \"intentional\"."
```

Sample report excerpt the agent would see:

```yaml
# dartrics ai-report v1
snapshot:
  mode: cache
  changedFiles: 12 of 247
counts:
  violations: 30
  unused: 0
  staleDismissals: 0
  signals: 30
explain:
  - metric: cognitive-complexity
    rationale: |
      Sonar's Cognitive Complexity penalises nested control flow more
      heavily than McCabe's CC. Each new structure adds a base point;
      nesting multiplies it.
    refactorHints:
      - Extract the deepest branch into a named helper.
      - Replace `if/else if` chains with a typed dispatch.
      - Collapse boolean spaghetti via early returns.
violations:
  - file: lib/parser.dart
    id: a3f1c4e9b2d70218
    line: 42
    scope: Parser.parse
    metric: cognitive-complexity
    value: 24
    threshold: 15
    severity: warning
    coverage: 0.91
    branchCoverage: 0.78
    snippet: |
      …7 lines centred on line 42…
# Reference values from the resolved call graph — compare against intent.
# NOT verdicts. A high fan-in is not "bad"; a 0 fan-in on a public API is
# a possible wiring gap, not necessarily dead code. Use snapshot diffs to
# spot values that moved on this edit.
signals:
  - file: lib/parser.dart
    line: 42
    scope: Parser.parse
    kind: method
    fanInCallers: 7
    fanInCalls: 18
    fanOutCallees: 12
    fanOutCalls: 24
truncated:
  violations: 8
  signals: 41
```

On a clean run with no metric over threshold the `violations:` and `explain:` blocks are absent entirely; `signals:` keeps emitting because it is reference information, not a finding.

Five cues the agent should act on:

- **`counts:`** — the per-section totals for what this report includes. Read totals here; don't count `- file:` lines — violations, unused, staleDismissals, and signals all share that entry shape, so a grep across the report over-counts.
- **`id: a3f1c4e9b2d70218`** on the violation — stable across runs. If the same id reappears next iteration, the previous fix didn't actually drop the metric.
- **`coverage: 0.91` + `branchCoverage: 0.78`** — well-tested. Refactor risk is low; go ahead.
- **`signals:` for the same scope** — `fanInCallers: 7` enumerates the call sites that would have to follow a signature change; `fanOutCallees: 12` flags that the scope coordinates many other types (overlaps in spirit with `response-for-class`). Reference-only — feed it into the refactor / dismiss decision; do not treat it as a violation.
- **`truncated: { violations: 8, signals: 41 }`** — 8 more violations and 41 more signals below the cap. Section totals are `counts` plus `truncated`. Once the visible 30 violations are done, re-run without `--limit` to drain the rest.

dartrics also pairs well with a semantic review pass over the same diff: the deterministic report seeds the reviewer's attention in seconds (complexity hotspots, convention violations — things an LLM reads past as "inherently complex"), the agent adjudicates and covers the metric blind spots (cross-scope duplication, design depth, dead parameters only tests keep alive), and `dartrics regression` verifies the result. The two detect nearly disjoint finding sets — run both when the budget allows.

## 3. Apply (the agent edits code)

The agent either rewrites the scope or drops a dismiss directive.

**Refactor case** — the agent edits `lib/parser.dart::Parser.parse` per the refactorHints:

```dart
// Before — cognitive-complexity = 24
// After — extracted dispatch helper, cognitive-complexity = 11
```

**Dismiss case** — when the structure is load-bearing (state machine, exhaustive switch, decoder fan-out):

```dart
// dartrics:dismiss cognitive-complexity reason="Recursive descent parser; splitting per-token would hide the grammar"
Token parse(Token start) { ... }
```

Or in YAML, when the project requires `requireAuthor: true` / `requireTimestamp: true`:

```yaml
# dartrics-dismissals.yaml
version: 1
dismissals:
  - file: lib/parser.dart
    scope: Parser.parse
    metric: cognitive-complexity
    reason: "Recursive descent parser; splitting per-token would hide the grammar"
    by: claude-opus-4-7
    at: "2026-05-06T19:14:00Z"
```

If the agent's reason is too short or missing, the next dartrics run keeps the violation **live** and stamps it with `dismissalRejected: reason too short (need >= 20)`. The agent sees this on the next pass and amends. There's no silent "I tried to suppress it but it didn't take" failure mode.

A triage verdict that lives only in the conversation does not persist. If the agent judges a violation intentional but writes no dismiss, the verdict evaporates when the session ends and the same violation re-surfaces on every future run. Persisting each "leave it" call as a dismiss entry — comment or YAML — is what makes the loop converge; "N items intentionally left as-is" belongs in dismiss entries, not in a chat message. (Punt is the one exception: an open question for the operator is deliberately not a tracked artifact.)

## 4. Verify (the agent re-reads dartrics)

Two complementary checks.

**Per-scope diff:**

```bash
dartrics regression --before HEAD~1 --after HEAD --reporter ai
```

This emits a list of `MetricChange` entries — `improved` / `regressed` / `unchanged` / `added` / `removed` — per `(scope, metric)`. The classifier uses each metric's `MetricPolarity` so "down" metrics like CC count as improvements when they drop. A built-in cosmetic-split heuristic also flags PRs where the agent shuffled complexity into one-line helpers without actually reducing it (`tinyHelpersAdded ≥ 3 ∧ slocDelta > 4·helpers ∧ ccReduction < 2·helpers`).

**Strict pass for CI / final review:**

```bash
dartrics analyze --strict-dismiss --fatal-warnings
```

`--strict-dismiss` ignores every dismissal — both comment and YAML — so the operator (or CI) sees the raw triage list. Combined with `--fatal-warnings`, this exits non-zero if the codebase still has unsuppressed warnings, suitable as a pre-merge gate.

## The unused-detector loop

`dartrics analyze` already lists unreachable public declarations in the AI report as an `unused:` block. `dartrics unused` is the focused subcommand that emits only that block (no metric battery, no signals); reach for it when you specifically want a dead-code sweep:

```bash
dartrics unused --reporter ai
```

Read each `unused:` entry **as a question, not a verdict**. A 0-reachability reading can mean any of:

- **Genuine leftover** — call sites were removed and the implementation was left behind. Delete.
- **Unwired implementation** — the implementation landed but the caller integration never followed. Deleting here hides a real bug.
- **Reflective / generated consumer** — codegen makes calls the static graph can't see. Built-in keep-alive presets cover `@JsonSerializable`, `@reflectiveTest`, and the standard codegen toolchain; project-specific annotations may need to be added to the presets.

### Confirm before deleting

```bash
dartrics inspect <symbol> --direction up --depth 3
```

Empty upstream → the detector saw it correctly, safe to delete. Non-empty upstream → the detector missed an indirection; do **not** `--apply`. Investigate the missing wiring, file a bug, or extend the keep-alive presets.

### Apply

```bash
dartrics unused --apply
```

In-place deletion of unused top-level functions / classes / typedefs / extensions. Refuses on a dirty git tree so the deletion lands in its own diff (override with `--force` only if you've accepted the audit trade-off). `test/` and `integration_test/` are excluded by default — pass `--include-tests` to widen. Imports left dangling after deletion are cleaned up with `dart fix --apply` afterwards.

## When the metric alone isn't enough — `dartrics inspect`

The ai-report carries `signals:` (per-declaration fan-in / fan-out, reference-only — no thresholds, no severity) for the same scopes the metrics fire on. When a violation reads ambiguously — *should I refactor this hub, or is it correctly central?* — drill in:

```bash
dartrics inspect Parser.parse --direction up --depth 2 --reporter ai
```

The output is a YAML-shaped subgraph: matched anchors with their fan-in / fan-out signal, then upstream callers (`--direction up`) and / or downstream callees (`--direction down`) up to `--depth` edges away. Three common entry points for an agent:

* **Disambiguating an unused report** — before deleting an `unused:` entry, walk `--direction up --depth 3` to confirm no inbound edge exists. If something *was* wiring to it through an indirection the unused detector missed, the inspect output reveals the call site.
* **Sizing the blast radius of a CC / Cognitive refactor** — `--direction up --depth 2` enumerates the call sites that would have to follow a signature change.
* **Reading a coordinator's surface** — `--direction down --depth 2` on a scope with high `fanOutCallees` shows whether `response-for-class` is over-firing (the callees are siblings of the same protocol) or correctly firing (the callees span unrelated subsystems).

Inspect is **not part of the refactor / dismiss / punt decision**; it feeds that decision with structure that the metric value alone doesn't carry. There are no `md` or `sarif` reporters for `inspect` because the output is reference-only — there's no finding to render.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Same `id` keeps showing up | Refactor didn't actually drop the metric | Inspect `value` vs `threshold` delta; metric is still over the line |
| `dismissalRejected: reason too short` | `requireReason: true` (default) | Rewrite the reason to ≥ `minReasonLength` chars |
| `dismissalRejected: missing required by:` | `requireAuthor: true` in config | Add `by: <agent-id>` to the YAML entry; comment dismissals can't carry author |
| `exit 78` | `analysis_options.yaml` `dartrics:` block invalid | stderr message names the offending key; the JSON Schema (`dartrics-config.schema.json`) catches most of these in-editor |
| AI report empty after change | `--snapshot cache` filtered to changed files only | First run wrote the snapshot; subsequent runs need a code change or `--snapshot none` to see everything |
| AI report missing `explain:` | No metric fired | The `explain:` block only renders when at least one metric crossed a threshold; a clean run is a healthy run |

## Reference flag map

| Goal | Flag | Notes |
| --- | --- | --- |
| Pick the AI-shaped report | `--reporter ai` | Mandatory for AI loops |
| Filter to changed code | `--since <git-ref>` | Violations are scope-granular (diff hunks ∩ scope span); unused / signals are file-granular. Renames surface as the new path |
| Filter to changed bytes (no git) | `--snapshot cache` | Default; per-file sha256 |
| Cap output for token budget | `--limit <n>` | Applied per section (violations / unused / signals) after priority sort |
| Skip dismissals (audit) | `--strict-dismiss` | Exposes the raw triage list |
| Speed up resolution | `--concurrency <n>` | Defaults to host CPU count, clamped to 16 |
| Block on warnings | `--fatal-warnings` | Combine with `--strict-dismiss` for CI |
| Delete unused public-API declarations | `dartrics unused --apply` | In-place deletion of unused top-level functions / classes / typedefs / extensions. Refuses on a dirty git tree (override `--force`). `test/` excluded by default (override `--include-tests`). Run `dart fix --apply` afterwards to clean imports |
| Probe the call graph around a symbol | `dartrics inspect <symbol>` | `--depth N` (default 2), `--direction up\|down\|both` (default `both`). Reference-only; `ai` / `json` reporters. Feeds the refactor / dismiss / punt decision with structure the metric value alone doesn't carry. |

## What's outside this loop

- **Cross-PR memory** — dartrics doesn't track "this dismiss was rejected once; don't propose it again." Stay session-local for now.
- **Prompt templates per agent** — Claude Code, Cursor, Codex each have their own conventions. The shell-out pattern above works in all of them.
- **Watch mode** — the analyzer plugin (`plugins: dartrics` in `analysis_options.yaml`) covers IDE feedback. The CLI is run-on-demand by design.
''';
