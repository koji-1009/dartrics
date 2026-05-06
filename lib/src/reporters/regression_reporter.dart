import 'dart:convert';
import 'dart:io';

import 'package:dapper/dapper.dart';

import '../models/regression_report.dart';

/// Renders a [RegressionReport] in one of the supported formats. Lives
/// alongside the regular `Reporter` impls but with a different shape
/// (no `AnalysisReport` argument).
class RegressionReporter {
  const RegressionReporter();

  void report(RegressionReport report, IOSink sink, String format) {
    switch (format) {
      case 'json':
        const encoder = JsonEncoder.withIndent('  ');
        sink.writeln(encoder.convert(report.toJson()));
        return;
      case 'md':
        sink.write(formatMarkdown(_renderMarkdown(report)));
        return;
      case 'console':
        sink.write(_renderConsole(report));
        return;
      case 'ai':
      default:
        sink.write(formatYaml(_renderAi(report)));
        return;
    }
  }

  String _renderAi(RegressionReport report) {
    final buf = StringBuffer()
      ..writeln('# dartrics regression v1')
      ..writeln('before: ${report.before}')
      ..writeln('after: ${report.after}')
      ..writeln('summary:')
      ..writeln('  improved: ${report.summary.improved}')
      ..writeln('  regressed: ${report.summary.regressed}')
      ..writeln('  unchanged: ${report.summary.unchanged}')
      ..writeln('  neutralDelta: ${report.summary.neutralDelta}')
      ..writeln('  added: ${report.summary.added}')
      ..writeln('  removed: ${report.summary.removed}');
    if (report.cosmetic.looksCosmetic) {
      buf
        ..writeln('warning: |')
        ..writeln(
          '  This refactor looks cosmetic: ${report.cosmetic.tinyHelpersAdded} '
          'new functions with bodies <= ${report.cosmetic.smallBodyThreshold} '
          'lines were added; total SLOC grew by ${report.cosmetic.slocDelta} '
          'while cyclomatic complexity only dropped by '
          '${report.cosmetic.ccReduction}. Consider whether the refactor '
          'actually improved readability or just spread the same logic across '
          'more methods.',
        );
    }
    if (report.changes.isEmpty) return buf.toString();
    buf.writeln('changes:');
    for (final c in report.changes) {
      buf
        ..writeln('  - file: ${c.file}')
        ..writeln('    scope: ${c.scope.name}')
        ..writeln('    metric: ${c.metricId}')
        ..writeln('    before: ${c.before ?? "null"}')
        ..writeln('    after: ${c.after ?? "null"}')
        ..writeln('    direction: ${c.direction.name}');
    }
    return buf.toString();
  }

  String _renderMarkdown(RegressionReport report) {
    final buf = StringBuffer()
      ..writeln('# dartrics regression report')
      ..writeln()
      ..writeln('`${report.before}` → `${report.after}`')
      ..writeln()
      ..writeln('| Direction | Count |')
      ..writeln('|-----------|-------|')
      ..writeln('| improved | ${report.summary.improved} |')
      ..writeln('| regressed | ${report.summary.regressed} |')
      ..writeln('| unchanged | ${report.summary.unchanged} |')
      ..writeln('| neutralDelta | ${report.summary.neutralDelta} |')
      ..writeln('| added | ${report.summary.added} |')
      ..writeln('| removed | ${report.summary.removed} |')
      ..writeln();
    if (report.cosmetic.looksCosmetic) {
      buf
        ..writeln('## ⚠️ Cosmetic-split warning')
        ..writeln()
        ..writeln(
          '${report.cosmetic.tinyHelpersAdded} new tiny helpers '
          '(SLOC <= ${report.cosmetic.smallBodyThreshold}); '
          'total SLOC delta ${report.cosmetic.slocDelta}; '
          'CC reduction ${report.cosmetic.ccReduction}.',
        )
        ..writeln();
    }
    if (report.changes.isEmpty) return buf.toString();
    buf
      ..writeln('## Changes')
      ..writeln();
    for (final c in report.changes) {
      buf.writeln(
        '- `${c.file}` `${c.scope.name}` `${c.metricId}`: '
        '${c.before ?? "—"} → ${c.after ?? "—"} (${c.direction.name})',
      );
    }
    buf.writeln();
    return buf.toString();
  }

  String _renderConsole(RegressionReport report) {
    final buf = StringBuffer()
      ..writeln(
        'dartrics regression: ${report.before} -> ${report.after}; '
        '${report.summary.improved} improved, '
        '${report.summary.regressed} regressed, '
        '${report.summary.added} added, '
        '${report.summary.removed} removed.',
      );
    if (report.cosmetic.looksCosmetic) {
      buf.writeln(
        'WARNING: refactor looks cosmetic '
        '(${report.cosmetic.tinyHelpersAdded} tiny helpers added; '
        'SLOC delta ${report.cosmetic.slocDelta}; '
        'CC reduction ${report.cosmetic.ccReduction}).',
      );
    }
    for (final c in report.changes) {
      if (c.direction == ChangeDirection.unchanged) continue;
      buf.writeln(
        '${c.file}::${c.scope.name} ${c.metricId} '
        '${c.before ?? "-"} -> ${c.after ?? "-"} [${c.direction.name}]',
      );
    }
    return buf.toString();
  }
}
