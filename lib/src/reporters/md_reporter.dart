import 'dart:io';

import 'package:dapper/dapper.dart';

import '../models/analysis_report.dart';
import 'reporter.dart';

/// Markdown reporter for PR comments and issue bodies.
///
/// Emits a fixed-section layout — `# dartrics report` → summary table →
/// per-violation details → unused declarations — and runs the final string
/// through `package:dapper`'s `formatMarkdown` so table column widths,
/// bullet indentation, and trailing newlines match the project's
/// Prettier-style canonical formatting.
class MdReporter implements Reporter {
  @override
  void report(AnalysisReport report, IOSink sink) {
    final buffer = StringBuffer()
      ..writeln('# dartrics report')
      ..writeln();
    _writeSummary(buffer, report);
    _writeExplanations(buffer, report);
    _writeViolations(buffer, report);
    _writeUnused(buffer, report);
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
    for (final s in ['error', 'warning', 'info']) {
      buf.writeln('| $s | ${counts[s] ?? 0} |');
    }
    buf
      ..writeln('| unused declarations | ${report.unused.length} |')
      ..writeln('| analyzed files | ${report.analyzedFileCount} |')
      ..writeln();
  }

  void _writeViolations(StringBuffer buf, AnalysisReport report) {
    final withViolations = report.metrics
        .where((m) => m.violations.isNotEmpty)
        .toList();
    if (withViolations.isEmpty) return;
    buf
      ..writeln('## Violations')
      ..writeln();
    for (final m in withViolations) {
      buf.writeln(
        '### `${m.file}:${m.scope.location.line}` — `${m.scope.name}`',
      );
      buf.writeln();
      for (final v in m.violations) {
        final cov = v.scopeCoverage;
        final justified = v.complexityJustified;
        final suffix = StringBuffer();
        if (v.id.isNotEmpty) suffix.write(' · `${v.id}`');
        if (cov != null) {
          suffix.write(' · coverage ${(cov * 100).toStringAsFixed(0)}%');
        }
        if (justified) suffix.write(' · _earned_');
        if (v.dismissed) suffix.write(' · _dismissed_');
        if (v.dismissalRejected != null) {
          suffix.write(' · _dismissal-rejected_');
        }
        buf.writeln(
          '- ${v.metricId}: **${m.values[v.metricId]}** '
          '(${v.severity.name} at ${v.threshold})$suffix',
        );
      }
      buf.writeln();
    }
  }

  void _writeUnused(StringBuffer buf, AnalysisReport report) {
    if (report.unused.isEmpty) return;
    buf
      ..writeln('## Unused Declarations')
      ..writeln();
    for (final u in report.unused) {
      buf.writeln(
        '- `${u.location.path}:${u.location.line}` — ${u.kind.name} `${u.name}`',
      );
    }
    buf.writeln();
  }
}
