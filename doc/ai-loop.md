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
| `--since origin/main` | Only emit records for files changed in the current branch. Avoids re-litigating debt the agent isn't there to fix. |
| `--limit 30` | Hard cap so a 1000-violation legacy codebase doesn't blow the context window. The truncated count is stamped into the report. |
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
truncated:
  violations: 8
```

Three signals the agent should act on:

- **`id: a3f1c4e9b2d70218`** — stable across runs. If the same id reappears next iteration, the previous fix didn't actually drop the metric.
- **`coverage: 0.91` + `branchCoverage: 0.78`** — well-tested. Refactor risk is low; go ahead.
- **`truncated: { violations: 8 }`** — there are 8 more below the cap. Once the visible 30 are done, re-run without `--limit`.

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
| Filter to changed files | `--since <git-ref>` | Renames surface as the new path |
| Filter to changed bytes (no git) | `--snapshot cache` | Default; per-file sha256 |
| Cap output for token budget | `--limit <n>` | Applied after priority sort |
| Skip dismissals (audit) | `--strict-dismiss` | Exposes the raw triage list |
| Speed up resolution | `--concurrency <n>` | Defaults to host CPU count, clamped to 16 |
| Block on warnings | `--fatal-warnings` | Combine with `--strict-dismiss` for CI |

## What's outside this loop

- **Cross-PR memory** — dartrics doesn't track "this dismiss was rejected once; don't propose it again." Stay session-local for now.
- **Prompt templates per agent** — Claude Code, Cursor, Codex each have their own conventions. The shell-out pattern above works in all of them.
- **Watch mode** — the analyzer plugin (`plugins: dartrics` in `analysis_options.yaml`) covers IDE feedback. The CLI is run-on-demand by design.
