import 'dart:io';

import 'package:dapper/dapper.dart';

import '../models/analysis_report.dart';
import '../models/unused_declaration.dart';
import 'reporter.dart';

/// Markdown reporter for PR comments and issue bodies.
///
/// Emits a fixed-section layout — `# dartrics report` → summary table →
/// per-violation details → unused declarations — and runs the final string
/// through `package:dapper`'s `formatMarkdown` so table column widths,
/// bullet indentation, and trailing newlines match the project's
/// Prettier-style canonical formatting.
class MdReporter implements Reporter {
  MdReporter({this.limit});

  /// Cap on the number of violation bullets rendered (after the
  /// existing record order). `null` keeps every bullet; a positive
  /// integer truncates and appends a `_+ N more violations_` line so
  /// reviewers see what was hidden.
  final int? limit;

  @override
  void report(AnalysisReport report, IOSink sink) {
    final buffer = StringBuffer()
      ..writeln('# dartrics report')
      ..writeln();
    _writeSummary(buffer, report);
    _writeExplanations(buffer, report);
    _writeViolations(buffer, report);
    _writeUnused(buffer, report);
    _writeStaleDismissals(buffer, report);
    sink.write(formatMarkdown(buffer.toString()));
  }

  void _writeExplanations(StringBuffer buf, AnalysisReport report) {
    if (report.explanations.isEmpty) return;
    buf
      ..writeln('## Explanations')
      ..writeln();
    for (final e in report.explanations) {
      buf
        ..writeln('### `${e.metricId}`')
        ..writeln()
        ..writeln(e.rationale)
        ..writeln()
        ..writeln('**Refactor hints:**')
        ..writeln();
      for (final hint in e.refactorHints) {
        buf.writeln('- $hint');
      }
      if (e.references.isNotEmpty) {
        buf
          ..writeln()
          ..writeln('**References:**')
          ..writeln();
        for (final ref in e.references) {
          buf.writeln('- $ref');
        }
      }
      buf.writeln();
    }
  }

  void _writeSummary(StringBuffer buf, AnalysisReport report) {
    final counts = <String, int>{};
    for (final m in report.metrics) {
      for (final v in m.violations) {
        counts.update(v.severity.name, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    buf
      ..writeln('## Summary')
      ..writeln()
      ..writeln('| Severity | Count |')
      ..writeln('|----------|-------|');
    for (final s in ['error', 'warning']) {
      buf.writeln('| $s | ${counts[s] ?? 0} |');
    }
    buf
      ..writeln('| unused declarations | ${report.unused.length} |')
      ..writeln('| analyzed files | ${report.analyzedFileCount} |')
      ..writeln('| snapshot mode | ${report.snapshotMode} |');
    final changed = report.changedFileCount;
    if (changed != null) {
      // Without this row, `cache` mode's second-run filter looks like
      // every violation suddenly evaporated — `unused declarations | 0`
      // is otherwise indistinguishable from "really nothing fired".
      final hint = changed == 0 ? ' (no new findings)' : '';
      buf.writeln(
        '| files changed | $changed of ${report.analyzedFileCount}$hint |',
      );
    }
    buf.writeln();
  }

  void _writeViolations(StringBuffer buf, AnalysisReport report) {
    final withViolations = report.metrics
        .where((m) => m.violations.isNotEmpty)
        .toList();
    if (withViolations.isEmpty) return;
    final totalBullets = withViolations.fold<int>(
      0,
      (sum, m) => sum + m.violations.length,
    );
    final cap = limit;
    var written = 0;
    buf
      ..writeln('## Violations')
      ..writeln();
    for (final m in withViolations) {
      // Stop at the record level so we don't leave a dangling heading
      // with no bullets under it.
      if (cap != null && written >= cap) break;
      buf.writeln(
        '### `${m.file}:${m.scope.location.line}` — `${m.scope.name}`',
      );
      buf.writeln();
      for (final v in m.violations) {
        if (cap != null && written >= cap) break;
        _writeViolationBullet(buf, m, v);
        written += 1;
      }
      buf.writeln();
    }
    final dropped = totalBullets - written;
    if (dropped > 0) {
      buf
        ..writeln('_+ $dropped more violation(s) hidden by --limit_')
        ..writeln();
    }
  }

  void _writeViolationBullet(
    StringBuffer buf,
    MetricRecord m,
    MetricViolation v,
  ) {
    buf.writeln(
      '- ${v.metricId}: **${m.values[v.metricId]}** '
      '(${v.severity.name} at ${v.threshold})${_bulletSuffix(v)}',
    );
  }

  String _bulletSuffix(MetricViolation v) {
    final suffix = StringBuffer();
    if (v.id.isNotEmpty) suffix.write(' · `${v.id}`');
    final cov = v.scopeCoverage;
    if (cov != null) {
      suffix.write(' · coverage ${(cov * 100).toStringAsFixed(0)}%');
    }
    if (v.complexityJustified) suffix.write(' · _earned_');
    if (v.dismissed) suffix.write(' · _dismissed_');
    if (v.dismissalRejected != null) suffix.write(' · _dismissal-rejected_');
    return suffix.toString();
  }

  void _writeUnused(StringBuffer buf, AnalysisReport report) {
    if (report.unused.isEmpty) return;
    buf
      ..writeln('## Unused Declarations')
      ..writeln();
    for (final u in report.unused) {
      buf.writeln(
        '- `${u.location.path}:${u.location.line}` — ${unusedKindJsonName(u.kind)} `${u.name}`',
      );
    }
    buf.writeln();
  }

  /// Lists dismissals that no longer match a live violation, so a human
  /// reviewer can prune the dismiss file. Mirrors the AI reporter's
  /// `staleDismissals:` block (which existed first); the MD reporter
  /// previously omitted this section, which left human reviewers blind
  /// to dead dismissal entries during PR review.
  void _writeStaleDismissals(StringBuffer buf, AnalysisReport report) {
    if (report.staleDismissals.isEmpty) return;
    buf
      ..writeln('## Stale Dismissals')
      ..writeln();
    for (final s in report.staleDismissals) {
      final reason = (s.reason != null && s.reason!.isNotEmpty)
          ? ' — _${s.reason}_'
          : '';
      buf.writeln(
        '- `${s.file}` · `${s.scope}` · ${s.metricId} · ${s.source.name}$reason',
      );
    }
    buf.writeln();
  }
}
