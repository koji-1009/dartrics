import 'dart:io';

import 'package:dapper/dapper.dart';

import '../models/analysis_report.dart';
import 'reporter.dart';

/// LLM-optimized reporter — emits only the violations and unused
/// declarations along with a 3-line code snippet around each location.
/// Output is YAML-ish (more token-efficient than JSON) and is finally
/// pretty-printed through `dapper`'s YAML formatter so column alignment
/// stays predictable for downstream agents.
class AiReporter implements Reporter {
  AiReporter({
    Map<String, String> Function(String path)? sourceLoader,
    this.limit,
  }) : _sourceLoader = sourceLoader ?? _defaultSourceLoader;

  final Map<String, String> Function(String path) _sourceLoader;

  /// Cap on the number of violations + unused entries written. `null`
  /// keeps every entry; a positive integer truncates after the priority
  /// sort and adds a `truncated:` summary block.
  final int? limit;

  /// Cache of file → lines so we don't re-read the same source repeatedly.
  final _lineCache = <String, List<String>>{};

  @override
  void report(AnalysisReport report, IOSink sink) {
    const header = '# dartrics ai-report v1';
    final body = StringBuffer();
    _writeExplanations(body, report);
    final dropped = _writeViolations(body, report);
    final unusedDropped = _writeUnused(body, report);
    _writeStaleDismissals(body, report);
    if (dropped > 0 || unusedDropped > 0) {
      body.writeln('truncated:');
      if (dropped > 0) body.writeln('  violations: $dropped');
      if (unusedDropped > 0) body.writeln('  unused: $unusedDropped');
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
        buf.writeln('      - ${_escape(hint)}');
      }
    }
  }

  String _escape(String value) {
    if (value.contains(':') || value.contains('#')) {
      return '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
    }
    return value;
  }

  /// Returns the number of violations dropped to honour [limit].
  int _writeViolations(StringBuffer buf, AnalysisReport report) {
    final entries = <_ViolationEntry>[
      for (final m in report.metrics)
        for (final v in m.violations) _ViolationEntry(record: m, violation: v),
    ];
    if (entries.isEmpty) return 0;
    entries.sort(_compareViolations);
    final keep = limit == null || entries.length <= limit!
        ? entries
        : entries.sublist(0, limit!);
    final dropped = entries.length - keep.length;
    buf.writeln('violations:');
    for (final e in keep) {
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
      if (v.scopeCoverage != null) {
        buf.writeln('    coverage: ${v.scopeCoverage!.toStringAsFixed(2)}');
      }
      if (v.scopeBranchCoverage != null) {
        buf.writeln(
          '    branchCoverage: ${v.scopeBranchCoverage!.toStringAsFixed(2)}',
        );
      }
      if (v.complexityJustified) {
        buf.writeln('    complexityJustified: true');
      }
      if (v.dismissed) {
        buf.writeln('    dismissed: true');
        if (v.dismissedFrom != null) {
          buf.writeln('    dismissedFrom: ${v.dismissedFrom!.name}');
        }
        if (v.dismissReason != null && v.dismissReason!.isNotEmpty) {
          buf.writeln('    dismissReason: ${_escape(v.dismissReason!)}');
        }
        if (v.dismissedBy != null) {
          buf.writeln('    dismissedBy: ${_escape(v.dismissedBy!)}');
        }
        if (v.dismissedAt != null) {
          buf.writeln(
            '    dismissedAt: ${_escape(v.dismissedAt!.toIso8601String())}',
          );
        }
      }
      if (v.dismissalRejected != null) {
        buf.writeln('    dismissalRejected: ${_escape(v.dismissalRejected!)}');
      }
      buf.writeln('    snippet: |');
      for (final line in _snippetFor(m.file, m.scope.location.line)) {
        buf.writeln('      $line');
      }
    }
    return dropped;
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

  /// Returns the number of unused entries dropped to honour [limit].
  int _writeUnused(StringBuffer buf, AnalysisReport report) {
    if (report.unused.isEmpty) return 0;
    final keep = limit == null || report.unused.length <= limit!
        ? report.unused
        : report.unused.sublist(0, limit!);
    final dropped = report.unused.length - keep.length;
    buf.writeln('unused:');
    for (final u in keep) {
      buf
        ..writeln('  - file: ${u.location.path}')
        ..writeln('    line: ${u.location.line}')
        ..writeln('    kind: ${u.kind.name}')
        ..writeln('    name: ${u.name}')
        ..writeln('    snippet: |');
      for (final line in _snippetFor(u.location.path, u.location.line)) {
        buf.writeln('      $line');
      }
    }
    return dropped;
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
        buf.writeln('    reason: ${_escape(s.reason!)}');
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
