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
  AiReporter({Map<String, String> Function(String path)? sourceLoader})
    : _sourceLoader = sourceLoader ?? _defaultSourceLoader;

  final Map<String, String> Function(String path) _sourceLoader;

  /// Cache of file → lines so we don't re-read the same source repeatedly.
  final _lineCache = <String, List<String>>{};

  @override
  void report(AnalysisReport report, IOSink sink) {
    final buf = StringBuffer()..writeln('# dartrics ai-report v1');
    _writeExplanations(buf, report);
    _writeViolations(buf, report);
    _writeUnused(buf, report);
    sink.write(formatYaml(buf.toString()));
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

  void _writeViolations(StringBuffer buf, AnalysisReport report) {
    final list = report.metrics.where((m) => m.violations.isNotEmpty).toList();
    if (list.isEmpty) return;
    buf.writeln('violations:');
    for (final m in list) {
      for (final v in m.violations) {
        buf
          ..writeln('  - file: ${m.file}')
          ..writeln('    line: ${m.scope.location.line}')
          ..writeln('    scope: ${m.scope.name}')
          ..writeln('    metric: ${v.metricId}')
          ..writeln('    value: ${m.values[v.metricId]}')
          ..writeln('    threshold: ${v.threshold}')
          ..writeln('    severity: ${v.severity.name}')
          ..writeln('    snippet: |');
        for (final line in _snippetFor(m.file, m.scope.location.line)) {
          buf.writeln('      $line');
        }
      }
    }
  }

  void _writeUnused(StringBuffer buf, AnalysisReport report) {
    if (report.unused.isEmpty) return;
    buf.writeln('unused:');
    for (final u in report.unused) {
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
