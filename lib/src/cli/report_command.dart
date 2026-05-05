import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart';

import '../models/analysis_report.dart';
import '../models/source_location.dart';
import '../models/unused_declaration.dart';
import '../reporters/reporters.dart';
import 'common_options.dart';

/// `dartrics report` — re-emits a previously persisted JSON report in
/// another format. Useful for converting a cached `metrics.json` into Markdown
/// for a PR comment, or into SARIF for a code-scanning upload, without
/// re-running analysis.
class ReportCommand extends Command<int> {
  ReportCommand() {
    addCommonOptions(argParser);
  }

  @override
  String get description =>
      'Re-emit a previously saved report in a different format.';

  @override
  String get name => 'report';

  @override
  Future<int> run() async {
    final options = CommonOptions.from(this);
    if (options.rest.isEmpty) {
      stderr.writeln('Usage: dartrics report <input.json>');
      return ExitCode.usage.code;
    }
    final input = File(options.rest.first);
    if (!input.existsSync()) {
      stderr.writeln('${input.path}: file not found');
      return ExitCode.data.code;
    }
    final report = _decode(input.readAsStringSync());
    final reporter = pickReporter(options.reporter);
    final IOSink sink;
    final bool ownsSink;
    if (options.output == '-') {
      sink = stdout;
      ownsSink = false;
    } else {
      sink = File(options.output).openWrite();
      ownsSink = true;
    }
    try {
      reporter.report(report, sink);
    } finally {
      if (ownsSink) await sink.close();
    }
    return ExitCode.success.code;
  }
}

AnalysisReport _decode(String body) {
  final raw = jsonDecode(body) as Map<String, Object?>;
  return AnalysisReport(
    version: raw['version'] as String? ?? '1.0',
    metrics: ((raw['metrics'] as List?) ?? const [])
        .cast<Map<String, Object?>>()
        .map(_decodeRecord)
        .toList(),
    unused: ((raw['unused'] as List?) ?? const [])
        .cast<Map<String, Object?>>()
        .map(_decodeUnused)
        .toList(),
  );
}

MetricRecord _decodeRecord(Map<String, Object?> json) {
  final scope = json['scope']! as Map<String, Object?>;
  final values = (json['values'] as Map?)?.cast<String, num>() ?? const {};
  final violations = ((json['violations'] as List?) ?? const [])
      .cast<Map<String, Object?>>()
      .map(_decodeViolation)
      .toList();
  return MetricRecord(
    file: json['file'] as String,
    scope: ScopeRef(
      kind: ScopeKind.values.byName(scope['type'] as String),
      name: scope['name'] as String,
      location: SourceLocation(
        path: json['file'] as String,
        line: scope['line'] as int,
        column: 1,
      ),
    ),
    values: values,
    violations: violations,
  );
}

MetricViolation _decodeViolation(Map<String, Object?> json) {
  return MetricViolation(
    metricId: json['metric'] as String,
    severity: Severity.values.byName(json['level'] as String),
    threshold: json['threshold'] as num,
  );
}

UnusedDeclaration _decodeUnused(Map<String, Object?> json) {
  return UnusedDeclaration(
    kind: UnusedKind.values.byName(json['kind'] as String),
    name: json['name'] as String,
    location: SourceLocation(
      path: json['file'] as String,
      line: json['line'] as int,
      column: 1,
    ),
  );
}
