import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart';

import '../metrics/metric_catalogue.dart';
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
