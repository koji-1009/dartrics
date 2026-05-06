import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart';

import '../metrics/class/default_class_metrics.dart';
import '../metrics/function/default_function_metrics.dart';
import '../metrics/library/default_library_metrics.dart';
import '../models/analysis_report.dart';
import '../reporters/rules_reporter.dart';

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
      sink = stdout;
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

/// Built-in default thresholds, mirroring the values baked into the
/// analyzer-plugin rule classes. Keeping them here means the `rules`
/// catalogue stays in sync without forcing the lint package onto
/// embedders that only want the CLI metrics.
const Map<String, num> defaultMetricThresholds = {
  'cyclomatic-complexity': 10,
  'cognitive-complexity': 15,
  'maximum-nesting-level': 4,
  'number-of-parameters': 4,
  'boolean-trap': 2,
};

/// Aggregates every default metric calculator into a list of
/// [RuleDescription]s.
List<RuleDescription> collectRuleDescriptions() {
  return [
    for (final m in defaultFunctionMetrics)
      RuleDescription(
        id: m.id,
        scope: 'function',
        defaultEnabled: m.defaultEnabled,
        defaultThreshold: defaultMetricThresholds[m.id],
        rationale: m.rationale,
        refactorHints: m.refactorHints,
      ),
    for (final m in defaultClassMetrics)
      RuleDescription(
        id: m.id,
        scope: 'class',
        defaultEnabled: m.defaultEnabled,
        defaultThreshold: defaultMetricThresholds[m.id],
        rationale: m.rationale,
        refactorHints: m.refactorHints,
      ),
    for (final m in defaultLibraryMetrics)
      RuleDescription(
        id: m.id,
        scope: 'library',
        defaultEnabled: m.defaultEnabled,
        defaultThreshold: defaultMetricThresholds[m.id],
        rationale: m.rationale,
        refactorHints: m.refactorHints,
      ),
  ];
}

/// Returns the [RuleDescription] for [metricId], or `null` if it is not
/// among the built-in metrics.
RuleDescription? findRuleDescription(String metricId) {
  for (final r in collectRuleDescriptions()) {
    if (r.id == metricId) return r;
  }
  return null;
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
      stderr.writeln('dartrics: --explain: unknown metric "$id"');
      continue;
    }
    out.add(
      ExplainEntry(
        metricId: desc.id,
        rationale: desc.rationale,
        refactorHints: desc.refactorHints,
      ),
    );
  }
  return out;
}
