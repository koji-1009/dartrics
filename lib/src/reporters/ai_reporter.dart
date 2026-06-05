import 'dart:io';

import 'package:dapper/dapper.dart';

import '../models/analysis_report.dart';
import '../models/call_graph_signal.dart';
import '../models/unused_declaration.dart';
import 'reporter.dart';
import 'yaml_scalar.dart';

/// LLM-optimized reporter — emits the violations and unused
/// declarations along with a 7-line code snippet around each location
/// (`line ± 3`), prefixed by a `counts:` block so agents read section
/// totals from one place instead of re-counting entry lines.
/// Output is YAML-ish (more token-efficient than JSON) and is finally
/// pretty-printed through `dapper`'s YAML formatter so column alignment
/// stays predictable for downstream agents.
class AiReporter implements Reporter {
  AiReporter({
    Map<String, String> Function(String path)? sourceLoader,
    this.limit,
  }) : _sourceLoader = sourceLoader ?? _defaultSourceLoader;

  final Map<String, String> Function(String path) _sourceLoader;

  /// Per-section cap on the number of entries written — the
  /// `violations:`, `unused:`, and `signals:` sections are each
  /// truncated independently. `null` keeps every entry; a positive
  /// integer truncates after the priority sort and adds a `truncated:`
  /// summary block with the dropped count per section.
  final int? limit;

  /// Cache of file → lines so we don't re-read the same source repeatedly.
  final _lineCache = <String, List<String>>{};

  @override
  void report(AnalysisReport report, IOSink sink) {
    const header = '# dartrics ai-report v1';
    final body = StringBuffer();
    _writeSnapshotStatus(body, report);
    final violations = _collectViolations(report);
    final sortedSignals = [...report.signals]
      ..sort(CallGraphSignal.byConnectivity);
    final keptViolations = _cap(violations);
    final keptUnused = _cap(report.unused);
    final keptSignals = _cap(sortedSignals);
    _writeCounts(
      body,
      violations: keptViolations.length,
      unused: keptUnused.length,
      staleDismissals: report.staleDismissals.length,
      signals: keptSignals.length,
    );
    _writeExplanations(body, report);
    _writeViolations(body, keptViolations);
    _writeUnused(body, keptUnused);
    _writeStaleDismissals(body, report);
    _writeSignals(body, keptSignals);
    final dropped = violations.length - keptViolations.length;
    final unusedDropped = report.unused.length - keptUnused.length;
    final signalsDropped = sortedSignals.length - keptSignals.length;
    if (dropped > 0 || unusedDropped > 0 || signalsDropped > 0) {
      body.writeln('truncated:');
      if (dropped > 0) body.writeln('  violations: $dropped');
      if (unusedDropped > 0) body.writeln('  unused: $unusedDropped');
      if (signalsDropped > 0) body.writeln('  signals: $signalsDropped');
    }
    // `package:dapper` 1.4.6 returns 'null<comment>\n' when fed a
    // comment-only string (no parseable body). On a clean codebase the
    // ai report is exactly that — header + nothing — so we bypass
    // dapper and write the header directly. The header alone is a
    // valid YAML document (a single comment line).
    if (body.isEmpty) {
      sink.writeln(header);
      return;
    }
    final full = StringBuffer()
      ..writeln(header)
      ..write(body.toString());
    sink.write(formatYaml(full.toString()));
  }

  /// Surfaces snapshot mode + diff filter so a `0`-everything report
  /// reads as "nothing fired in the changed file set" rather than
  /// "nothing fired at all". Skipped when no diff filter is active and
  /// snapshot mode is `none` — the AI loop has nothing to disambiguate.
  void _writeSnapshotStatus(StringBuffer buf, AnalysisReport report) {
    final changed = report.changedFileCount;
    if (changed == null && report.snapshotMode == 'none') return;
    buf
      ..writeln('snapshot:')
      ..writeln('  mode: ${report.snapshotMode}');
    if (changed != null) {
      buf.writeln('  changedFiles: $changed of ${report.analyzedFileCount}');
    }
  }

  void _writeExplanations(StringBuffer buf, AnalysisReport report) {
    if (report.explanations.isEmpty) return;
    buf.writeln('explain:');
    for (final e in report.explanations) {
      buf
        ..writeln('  - metric: ${e.metricId}')
        ..writeln('    rationale: |')
        ..writeln('      ${e.rationale.replaceAll('\n', '\n      ')}')
        ..writeln('    refactorHints:');
      for (final hint in e.refactorHints) {
        buf.writeln('      - ${yamlInlineScalar(hint)}');
      }
      if (e.references.isNotEmpty) {
        buf.writeln('    references:');
        for (final ref in e.references) {
          buf.writeln('      - ${yamlInlineScalar(ref)}');
        }
      }
    }
  }

  /// Flattens the per-record violations into sorted entries. The sort
  /// happens here so [_cap] truncates the least actionable tail.
  List<_ViolationEntry> _collectViolations(AnalysisReport report) {
    final entries = <_ViolationEntry>[
      for (final m in report.metrics)
        for (final v in m.violations) _ViolationEntry(record: m, violation: v),
    ];
    entries.sort(_compareViolations);
    return entries;
  }

  /// Applies [limit] to a section's entry list. Each section is capped
  /// independently — `--limit 30` keeps up to 30 violations AND up to
  /// 30 unused entries AND up to 30 signals.
  List<T> _cap<T>(List<T> all) =>
      limit == null || all.length <= limit! ? all : all.sublist(0, limit!);

  /// Emits the per-section entry counts so agents read totals from one
  /// place instead of grepping for `- file:` lines — those appear in
  /// four different sections, so a naive grep over-counts. Skipped when
  /// every section is empty AND no snapshot block was written (the
  /// header-only clean report stays a single line).
  void _writeCounts(
    StringBuffer buf, {
    required int violations,
    required int unused,
    required int staleDismissals,
    required int signals,
  }) {
    final allEmpty =
        violations == 0 && unused == 0 && staleDismissals == 0 && signals == 0;
    if (allEmpty && buf.isEmpty) return;
    buf
      ..writeln('# Entries included per section. With --limit, dropped tails')
      ..writeln(
        '# land in a trailing truncated block (total = counts + drops).',
      )
      ..writeln('counts:')
      ..writeln('  violations: $violations')
      ..writeln('  unused: $unused')
      ..writeln('  staleDismissals: $staleDismissals')
      ..writeln('  signals: $signals');
  }

  void _writeViolations(StringBuffer buf, List<_ViolationEntry> kept) {
    if (kept.isEmpty) return;
    buf.writeln('violations:');
    for (final e in kept) {
      _writeViolation(buf, e);
    }
  }

  void _writeViolation(StringBuffer buf, _ViolationEntry e) {
    final m = e.record;
    final v = e.violation;
    buf.writeln('  - file: ${m.file}');
    if (v.id.isNotEmpty) buf.writeln('    id: ${v.id}');
    buf
      ..writeln('    line: ${m.scope.location.line}')
      ..writeln('    scope: ${m.scope.name}')
      ..writeln('    metric: ${v.metricId}')
      ..writeln('    value: ${m.values[v.metricId]}')
      ..writeln('    threshold: ${v.threshold}')
      ..writeln('    severity: ${v.severity.name}');
    _writeCoverage(buf, v);
    _writeJustification(buf, v);
    _writeDismiss(buf, v);
    if (v.dismissalRejected != null) {
      buf.writeln(
        '    dismissalRejected: ${yamlInlineScalar(v.dismissalRejected!)}',
      );
    }
    _writeSnippet(buf, m.file, m.scope.location.line);
  }

  void _writeCoverage(StringBuffer buf, MetricViolation v) {
    if (v.scopeCoverage != null) {
      buf.writeln('    coverage: ${v.scopeCoverage!.toStringAsFixed(2)}');
    }
    if (v.scopeBranchCoverage != null) {
      buf.writeln(
        '    branchCoverage: ${v.scopeBranchCoverage!.toStringAsFixed(2)}',
      );
    }
  }

  void _writeJustification(StringBuffer buf, MetricViolation v) {
    if (!v.complexityJustified) return;
    buf.writeln('    complexityJustified: true');
    if (v.complexityJustifiedBy != null) {
      buf.writeln('    complexityJustifiedBy: ${v.complexityJustifiedBy}');
    }
    if (v.complexityJustifiedThreshold != null) {
      buf.writeln(
        '    complexityJustifiedThreshold: '
        '${v.complexityJustifiedThreshold!.toStringAsFixed(2)}',
      );
    }
  }

  void _writeDismiss(StringBuffer buf, MetricViolation v) {
    if (!v.dismissed) return;
    buf.writeln('    dismissed: true');
    if (v.dismissedFrom != null) {
      buf.writeln('    dismissedFrom: ${v.dismissedFrom!.name}');
    }
    if (v.dismissReason != null && v.dismissReason!.isNotEmpty) {
      buf.writeln('    dismissReason: ${yamlInlineScalar(v.dismissReason!)}');
    }
    if (v.dismissedBy != null) {
      buf.writeln('    dismissedBy: ${yamlInlineScalar(v.dismissedBy!)}');
    }
    if (v.dismissedAt != null) {
      buf.writeln(
        '    dismissedAt: ${yamlInlineScalar(v.dismissedAt!.toIso8601String())}',
      );
    }
  }

  /// Emits the snippet block. `|2` pins the literal-block baseline to
  /// the parent indent + 2 spaces; without it, YAML auto-detect picks
  /// the indent off the first non-empty content line and a snippet
  /// whose centred line is deeper than later lines (e.g. closing `}`
  /// at column 0) makes dapper's re-parse pass abort. See
  /// `test/reporters/ai_reporter_test.dart` "round-trips through dapper".
  void _writeSnippet(StringBuffer buf, String path, int line) {
    buf.writeln('    snippet: |2');
    for (final l in _snippetFor(path, line)) {
      buf.writeln('      $l');
    }
  }

  /// Highest-severity, lowest-priority-key violations come first.
  /// Priority key collapses coverage + earned + dismissed into a single
  /// number: low coverage (most actionable) at 0.0, no coverage data
  /// in the middle (0.5), `complexityJustified` at 2.0, and `dismissed`
  /// entries at 3.0 — they sit at the very bottom because the user has
  /// already triaged them.
  int _compareViolations(_ViolationEntry a, _ViolationEntry b) {
    final bySev = b.violation.severity.rank.compareTo(
      a.violation.severity.rank,
    );
    if (bySev != 0) return bySev;
    return _priority(a.violation).compareTo(_priority(b.violation));
  }

  double _priority(MetricViolation v) {
    if (v.dismissed) return 3.0;
    if (v.complexityJustified) return 2.0;
    return v.scopeCoverage ?? 0.5;
  }

  void _writeUnused(StringBuffer buf, List<UnusedDeclaration> kept) {
    if (kept.isEmpty) return;
    buf
      ..writeln(
        '# Unused entries may be leftover code to delete OR unwired '
        'implementations',
      )
      ..writeln(
        '# (declared but never reached — possible wiring gap). Confirm '
        'against intent',
      )
      ..writeln('# before acting.')
      ..writeln('unused:');
    for (final u in kept) {
      buf
        ..writeln('  - file: ${u.location.path}')
        ..writeln('    line: ${u.location.line}')
        ..writeln('    kind: ${unusedKindJsonName(u.kind)}')
        ..writeln('    name: ${u.name}');
      _writeSnippet(buf, u.location.path, u.location.line);
    }
  }

  /// Emits per-declaration fan-in / fan-out as a `signals:` block.
  /// [kept] arrives sorted by [CallGraphSignal.byConnectivity] so the
  /// most-connected entries come first and the `0/0` tail is what
  /// `--limit` truncated.
  void _writeSignals(StringBuffer buf, List<CallGraphSignal> kept) {
    if (kept.isEmpty) return;
    buf
      ..writeln(
        '# Reference values from the resolved call graph — compare '
        'against intent.',
      )
      ..writeln(
        '# NOT verdicts. A high fan-in is not "bad"; a 0 fan-in on a '
        'public API is',
      )
      ..writeln(
        '# a possible wiring gap, not necessarily dead code. Use '
        'snapshot diffs to',
      )
      ..writeln('# spot values that moved on this edit.')
      ..writeln('signals:');
    for (final s in kept) {
      buf
        ..writeln('  - file: ${s.file}')
        ..writeln('    line: ${s.scope.location.line}')
        ..writeln('    scope: ${s.scope.name}')
        ..writeln('    kind: ${s.scope.kind.name}')
        ..writeln('    fanInCallers: ${s.fanInCallers}')
        ..writeln('    fanInCalls: ${s.fanInCalls}')
        ..writeln('    fanOutCallees: ${s.fanOutCallees}')
        ..writeln('    fanOutCalls: ${s.fanOutCalls}');
    }
  }

  /// Surfaces dismiss entries that never matched a live violation, so
  /// AI loops can prune the dismiss file. Emitted as a flat list with
  /// the source channel (`comment` / `yaml`) so the agent knows
  /// whether the cleanup is a source edit or a YAML edit. Skipped
  /// silently when the engine produced no stale entries (the typical
  /// case once the dismiss file is fresh).
  void _writeStaleDismissals(StringBuffer buf, AnalysisReport report) {
    if (report.staleDismissals.isEmpty) return;
    buf.writeln('staleDismissals:');
    for (final s in report.staleDismissals) {
      buf
        ..writeln('  - file: ${s.file}')
        ..writeln('    scope: ${s.scope}')
        ..writeln('    metric: ${s.metricId}')
        ..writeln('    source: ${s.source.name}');
      if (s.reason != null && s.reason!.isNotEmpty) {
        buf.writeln('    reason: ${yamlInlineScalar(s.reason!)}');
      }
    }
  }

  /// Returns up to 7 lines centered on [centerLine] (3 above, the line
  /// itself, 3 below). Out-of-range indices are skipped.
  List<String> _snippetFor(String path, int centerLine) {
    final lines = _lineCache.putIfAbsent(path, () {
      final loaded = _sourceLoader(path);
      return loaded.values.first.split('\n');
    });
    final lo = (centerLine - 4).clamp(0, lines.length);
    final hi = (centerLine + 3).clamp(0, lines.length);
    return lines.sublist(lo, hi);
  }
}

Map<String, String> _defaultSourceLoader(String path) {
  try {
    return {path: File(path).readAsStringSync()};
  } on FileSystemException {
    return {path: ''};
  }
}

class _ViolationEntry {
  const _ViolationEntry({required this.record, required this.violation});
  final MetricRecord record;
  final MetricViolation violation;
}
