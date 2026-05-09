import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart';

import '../metrics/metric_catalogue.dart';
import '../models/analysis_report.dart';
import '../reporters/rules_reporter.dart';
import 'io_sinks.dart';

export '../metrics/metric_catalogue.dart'
    show collectRuleDescriptions, defaultMetricThresholds, findRuleDescription;

/// `dartrics rules` — emits a catalogue of every metric this build of
/// dartrics ships, including its rationale and recommended refactors.
///
/// The output is meant for AI loops that need to know what each metric
/// measures without re-deriving it from training data, and for embedding
/// in README / docs (`--reporter md`).
class RulesCommand extends Command<int> {
  RulesCommand() {
    argParser
      ..addOption(
        'reporter',
        help: 'Output format.',
        allowed: ['ai', 'md', 'json', 'console'],
        defaultsTo: 'ai',
      )
      ..addOption(
        'output',
        help: 'Output destination. Use "-" for stdout.',
        defaultsTo: '-',
      );
  }

  @override
  String get name => 'rules';

  @override
  String get description =>
      'List every metric with its rationale and refactor hints.';

  @override
  Future<int> run() async {
    final results = argResults!;
    final reporter = results['reporter'] as String;
    final output = results['output'] as String;
    final descriptions = collectRuleDescriptions();
    final IOSink sink;
    final bool ownsSink;
    if (output == '-') {
      sink = DartricsIO.stdoutSink;
      ownsSink = false;
    } else {
      sink = File(output).openWrite();
      ownsSink = true;
    }
    try {
      const RulesReporter().report(descriptions, sink, reporter);
    } finally {
      if (ownsSink) {
        await sink.close();
      }
    }
    return ExitCode.success.code;
  }
}

/// Resolves the `--explain <metric-id>` option values to a list of
/// [ExplainEntry]s. Unknown ids are written to stderr but otherwise
/// silently dropped — callers stay in control of whether to fail.
List<ExplainEntry> buildExplanations(List<String> ids) {
  final out = <ExplainEntry>[];
  final seen = <String>{};
  for (final raw in ids) {
    final id = raw.trim();
    if (id.isEmpty || !seen.add(id)) continue;
    final desc = findRuleDescription(id);
    if (desc == null) {
      DartricsIO.stderrSink.writeln(
        'dartrics: --explain: unknown metric "$id"',
      );
      continue;
    }
    out.add(
      ExplainEntry(
        metricId: desc.id,
        rationale: desc.rationale,
        refactorHints: desc.refactorHints,
        references: desc.references,
      ),
    );
  }
  return out;
}
