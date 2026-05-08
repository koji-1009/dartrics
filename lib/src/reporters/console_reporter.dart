import 'dart:io';

import '../models/analysis_report.dart';
import '../models/unused_declaration.dart';
import 'reporter.dart';

/// Default reporter — prints a one-line summary plus per-violation entries.
class ConsoleReporter implements Reporter {
  @override
  void report(AnalysisReport report, IOSink sink) {
    sink.writeln(
      'dartrics: analyzed ${report.analyzedFileCount} file(s); '
      '${report.metrics.length} metric record(s), '
      '${report.unused.length} unused declaration(s)'
      '${_snapshotSuffix(report)}.',
    );
    for (final record in report.metrics) {
      for (final v in record.violations) {
        final tags = StringBuffer();
        if (v.dismissed) tags.write(' [dismissed]');
        if (v.dismissalRejected != null) tags.write(' [dismissal-rejected]');
        sink.writeln(
          '${record.file}:${record.scope.location.line} '
          '[${v.severity.name}] ${v.metricId} = ${record.values[v.metricId]} '
          '(threshold ${v.threshold}) in ${record.scope.name}$tags',
        );
      }
    }
    for (final u in report.unused) {
      sink.writeln(
        '${u.location.path}:${u.location.line} '
        '[unused] ${unusedKindJsonName(u.kind)} ${u.name}',
      );
    }
  }

  /// Tail-text appended to the summary line when a diff filter (`cache`
  /// snapshot or `--since`) was active, so a `0 unused` summary doesn't
  /// look indistinguishable from "really nothing fired".
  String _snapshotSuffix(AnalysisReport report) {
    final changed = report.changedFileCount;
    if (changed == null) return '';
    return ' [snapshot ${report.snapshotMode}: '
        '$changed of ${report.analyzedFileCount} changed]';
  }
}
