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
      case 'md':
        sink.write(formatMarkdown(_renderMarkdown(report)));
      case 'console':
        sink.write(_renderConsole(report));
      case 'ai' || _:
        sink.write(formatYaml(_renderAi(report)));
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
    if (_cosmeticHasSignal(report.cosmetic)) {
      buf
        ..writeln('cosmetic:')
        ..writeln('  tinyHelpersAdded: ${report.cosmetic.tinyHelpersAdded}')
        ..writeln('  slocDelta: ${report.cosmetic.slocDelta}')
        ..writeln('  ccReduction: ${report.cosmetic.ccReduction}')
        ..writeln('  smallBodyThreshold: ${report.cosmetic.smallBodyThreshold}')
        ..writeln('  looksCosmetic: ${report.cosmetic.looksCosmetic}');
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
    }
    if (report.changes.isEmpty) return buf.toString();
    buf.writeln('changes:');
    for (final c in report.changes) {
      buf
        ..writeln('  - file: ${c.file}')
        ..writeln('    scope: ${c.scope.name}')
        ..writeln('    metric: ${c.metricId}')
        ..writeln('    id: ${c.id}')
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
    if (_cosmeticHasSignal(report.cosmetic)) {
      buf
        ..writeln(
          report.cosmetic.looksCosmetic
              ? '## ⚠️ Cosmetic-split warning'
              : '## Cosmetic signals',
        )
        ..writeln()
        ..writeln(
          '- tinyHelpersAdded: ${report.cosmetic.tinyHelpersAdded} '
          '(bodies ≤ ${report.cosmetic.smallBodyThreshold} SLOC)',
        )
        ..writeln('- slocDelta: ${report.cosmetic.slocDelta}')
        ..writeln('- ccReduction: ${report.cosmetic.ccReduction}')
        ..writeln('- looksCosmetic: ${report.cosmetic.looksCosmetic}')
        ..writeln();
      if (report.cosmetic.looksCosmetic) {
        buf
          ..writeln(
            'The refactor looks cosmetic: helpers added without a '
            'matching CC reduction. Consider whether the refactor '
            'improved readability or just spread the same logic '
            'across more methods.',
          )
          ..writeln();
      }
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
    if (_cosmeticHasSignal(report.cosmetic)) {
      final prefix = report.cosmetic.looksCosmetic
          ? 'WARNING: refactor looks cosmetic — '
          : 'cosmetic signals: ';
      buf.writeln(
        '$prefix'
        '${report.cosmetic.tinyHelpersAdded} tiny helpers added; '
        'SLOC delta ${report.cosmetic.slocDelta}; '
        'CC reduction ${report.cosmetic.ccReduction}.',
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

  /// True when any cosmetic counter is non-zero. The reporters use this
  /// to decide whether to emit the cosmetic block at all — a refactor
  /// that adds 0 helpers, didn't move SLOC, and didn't change CC
  /// generates no signal worth showing.
  bool _cosmeticHasSignal(CosmeticSignals c) =>
      c.tinyHelpersAdded != 0 || c.slocDelta != 0 || c.ccReduction != 0;
}
