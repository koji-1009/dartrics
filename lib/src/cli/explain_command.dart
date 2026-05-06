import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dapper/dapper.dart';
import 'package:io/io.dart';

import '../metrics/metric_catalogue.dart';
import '../reporters/rules_reporter.dart';

/// `dartrics explain &lt;id&gt;` — looks up a violation by its stable
/// 16-hex-char id and prints the matching entry plus the metric's
/// rationale + refactor hints. Closes the loop on Round 4's stable id:
/// AI agents that see the same id reappear across runs ("my fix didn't
/// take") get a one-shot way to retrieve full context for that id
/// without re-reading the entire report.
///
/// Reads a JSON report (the format produced by `dartrics analyze
/// --reporter json`) from stdin or `--input &lt;path&gt;`. Emits YAML by
/// default for token-efficient AI consumption; `--reporter json` is
/// available for programmatic consumers.
class ExplainCommand extends Command<int> {
  ExplainCommand() {
    argParser
      ..addOption(
        'input',
        help:
            'Path to a JSON report from `dartrics analyze --reporter json`. '
            'Use "-" or omit for stdin.',
        defaultsTo: '-',
      )
      ..addOption(
        'reporter',
        help: 'Output format.',
        allowed: ['ai', 'json'],
        defaultsTo: 'ai',
      )
      ..addOption(
        'output',
        help: 'Output destination. Use "-" for stdout.',
        defaultsTo: '-',
      );
  }

  @override
  String get name => 'explain';

  @override
  String get description =>
      'Look up a violation by id and print its rationale + refactor hints.';

  @override
  Future<int> run() async {
    final results = argResults!;
    if (results.rest.isEmpty) {
      stderr.writeln('Usage: dartrics explain <id> [--input <report.json>]');
      return ExitCode.usage.code;
    }
    final id = results.rest.first;
    final input = results['input'] as String;
    final String body;
    try {
      body = await readReportBody(input);
    } on FileSystemException catch (e) {
      stderr.writeln('dartrics explain: ${e.message}: ${e.path}');
      return ExitCode.data.code;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (e) {
      stderr.writeln('dartrics explain: invalid JSON: ${e.message}');
      return ExitCode.data.code;
    }
    if (decoded is! Map<String, Object?>) {
      stderr.writeln('dartrics explain: top-level JSON must be an object');
      return ExitCode.data.code;
    }
    final raw = decoded;

    final found = findViolation(raw, id);
    if (found == null) {
      stderr.writeln('dartrics explain: no violation with id "$id"');
      return ExitCode.data.code;
    }

    final reporter = results['reporter'] as String;
    final output = results['output'] as String;
    final IOSink sink;
    final bool ownsSink;
    if (output == '-') {
      sink = stdout;
      ownsSink = false;
    } else {
      sink = File(output).openWrite();
      ownsSink = true;
    }
    try {
      _emit(found, reporter, sink);
    } finally {
      if (ownsSink) await sink.close();
    }
    return ExitCode.success.code;
  }

  void _emit(ExplainHit hit, String reporter, IOSink sink) {
    final desc = findRuleDescription(hit.metricId);
    if (reporter == 'json') {
      sink.writeln(
        const JsonEncoder.withIndent('  ').convert({
          'violation': hit.toJson(),
          if (desc != null) 'explain': _explainJson(desc),
        }),
      );
      return;
    }
    sink.write(formatYaml(_renderAi(hit, desc)));
  }

  Map<String, Object?> _explainJson(RuleDescription desc) => {
    'metric': desc.id,
    'polarity': desc.polarity,
    'rationale': desc.rationale,
    'refactorHints': desc.refactorHints,
  };

  String _renderAi(ExplainHit hit, RuleDescription? desc) {
    final buf = StringBuffer()
      ..writeln('# dartrics explain v1')
      ..writeln('violation:')
      ..writeln('  id: ${hit.id}')
      ..writeln('  file: ${hit.file}')
      ..writeln('  scope: ${hit.scopeName}')
      ..writeln('  line: ${hit.line}')
      ..writeln('  metric: ${hit.metricId}');
    if (hit.value != null) buf.writeln('  value: ${hit.value}');
    buf
      ..writeln('  threshold: ${hit.threshold}')
      ..writeln('  severity: ${hit.severity}');
    if (hit.scopeCoverage != null) {
      buf.writeln('  coverage: ${hit.scopeCoverage}');
    }
    if (hit.scopeBranchCoverage != null) {
      buf.writeln('  branchCoverage: ${hit.scopeBranchCoverage}');
    }
    if (hit.complexityJustified) {
      buf.writeln('  complexityJustified: true');
    }
    if (hit.dismissed) buf.writeln('  dismissed: true');
    if (hit.dismissalRejected != null) {
      buf.writeln(
        '  dismissalRejected: ${_yamlInline(hit.dismissalRejected!)}',
      );
    }
    if (desc != null) {
      buf
        ..writeln('explain:')
        ..writeln('  metric: ${desc.id}')
        ..writeln('  polarity: ${desc.polarity}')
        ..writeln('  rationale: |')
        ..writeln('    ${desc.rationale.replaceAll('\n', '\n    ')}')
        ..writeln('  refactorHints:');
      for (final h in desc.refactorHints) {
        buf.writeln('    - ${_yamlInline(h)}');
      }
    } else {
      buf.writeln(
        'explain: null  # metric "${hit.metricId}" not in built-in catalogue',
      );
    }
    return buf.toString();
  }

  String _yamlInline(String value) {
    if (value.contains(':') || value.contains('#') || value.contains('"')) {
      return '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
    }
    return value;
  }
}

/// One violation matched by id, with the parent record's contextual
/// fields flattened so the emitter can print everything from a single
/// struct. Exposed for tests + future programmatic consumers.
class ExplainHit {
  const ExplainHit({
    required this.id,
    required this.file,
    required this.scopeName,
    required this.line,
    required this.metricId,
    required this.threshold,
    required this.severity,
    this.value,
    this.scopeCoverage,
    this.scopeBranchCoverage,
    this.complexityJustified = false,
    this.dismissed = false,
    this.dismissalRejected,
  });

  final String id;
  final String file;
  final String scopeName;
  final int line;
  final String metricId;
  final num? value;
  final num threshold;
  final String severity;
  final num? scopeCoverage;
  final num? scopeBranchCoverage;
  final bool complexityJustified;
  final bool dismissed;
  final String? dismissalRejected;

  Map<String, Object?> toJson() => {
    'id': id,
    'file': file,
    'scope': scopeName,
    'line': line,
    'metric': metricId,
    if (value != null) 'value': value,
    'threshold': threshold,
    'severity': severity,
    if (scopeCoverage != null) 'coverage': scopeCoverage,
    if (scopeBranchCoverage != null) 'branchCoverage': scopeBranchCoverage,
    if (complexityJustified) 'complexityJustified': true,
    if (dismissed) 'dismissed': true,
    if (dismissalRejected != null) 'dismissalRejected': dismissalRejected,
  };
}

/// Reads the report body from either [stdin] (when [input] is `-`) or
/// the file at [input]. Extracted so unit tests can substitute a
/// synthetic `Stream<List<int>>` for stdin without going through
/// [IOOverrides].
Future<String> readReportBody(
  String input, {
  Stream<List<int>>? stdinSource,
}) async {
  if (input == '-') {
    return (stdinSource ?? stdin).transform(utf8.decoder).join();
  }
  return File(input).readAsString();
}

/// Walks the parsed JSON report shape (`{metrics: [{violations: [...]}]}`)
/// and returns the first [ExplainHit] matching [id], or `null`.
///
/// Tolerant about absent fields — callers may pipe a partial report (e.g.
/// from a different dartrics version) and the lookup should still
/// resolve when the basic identity fields are present.
ExplainHit? findViolation(Map<String, Object?> raw, String id) {
  final metrics = raw['metrics'];
  if (metrics is! List) return null;
  for (final entry in metrics) {
    if (entry is! Map<String, Object?>) continue;
    final violations = entry['violations'];
    if (violations is! List) continue;
    final scope = entry['scope'];
    final values = entry['values'];
    for (final v in violations) {
      if (v is! Map<String, Object?>) continue;
      if (v['id'] != id) continue;
      final metricId = v['metric'] as String? ?? '';
      return ExplainHit(
        id: id,
        file: entry['file'] as String? ?? '',
        scopeName: scope is Map ? scope['name'] as String? ?? '' : '',
        line: scope is Map ? (scope['line'] as int?) ?? 0 : 0,
        metricId: metricId,
        value: values is Map ? values[metricId] as num? : null,
        threshold: v['threshold'] as num? ?? 0,
        severity: v['level'] as String? ?? 'warning',
        scopeCoverage: v['scopeCoverage'] as num?,
        scopeBranchCoverage: v['scopeBranchCoverage'] as num?,
        complexityJustified: v['complexityJustified'] as bool? ?? false,
        dismissed: v['dismissed'] as bool? ?? false,
        dismissalRejected: v['dismissalRejected'] as String?,
      );
    }
  }
  return null;
}
