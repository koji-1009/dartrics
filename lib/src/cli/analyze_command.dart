import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart';

import '../analyzer_runner.dart';
import '../config/config.dart';
import '../config/config_loader.dart';
import '../metrics/metric_engine.dart';
import '../models/analysis_report.dart';
import '../reporters/reporters.dart';
import '../unused/unused_detector.dart';
import 'common_options.dart';
import 'git_diff.dart';
import 'rules_command.dart';

/// `dartrics analyze` — runs every metric calculator and the unused
/// detector over the analysis root and emits a combined report.
class AnalyzeCommand extends Command<int> {
  AnalyzeCommand() {
    addCommonOptions(argParser);
  }

  @override
  String get name => 'analyze';

  @override
  String get description => 'Compute code-quality metrics for a Dart package.';

  @override
  Future<int> run() async {
    final options = CommonOptions.from(this);
    final config = await loadConfig(options.configPath);
    final paths = options.rest.isNotEmpty
        ? options.rest
        : <String>[options.root];
    final Set<String>? changed;
    try {
      changed = await _resolveChangedFiles(options.since);
    } on GitDiffException catch (e) {
      stderr.writeln(e);
      return ExitCode.data.code;
    }
    final report = await _analyze(paths, config, changed, options.explain);
    return _emit(report, options);
  }

  Future<Set<String>?> _resolveChangedFiles(String? since) async {
    if (since == null) return null;
    return (await changedDartFilesSince(since)).toSet();
  }

  Future<AnalysisReport> _analyze(
    List<String> paths,
    Config config,
    Set<String>? changed,
    List<String> explainIds,
  ) async {
    final runner = AnalyzerRunner(roots: paths, exclude: config.exclude);
    final units = await runner.resolveAll();
    final engine = MetricEngine(
      thresholds: config.metricThresholds,
      flutter: config.flutter,
    );
    final records = engine.analyzeResolved(units);
    final unused = await const UnusedDetector().detect([
      for (final u in units)
        (path: u.path, unit: u.unit.unit, lineInfo: u.unit.lineInfo),
    ], config.unused);
    final filteredRecords = changed == null
        ? records
        : records.where((r) => changed.contains(r.file)).toList();
    final filteredUnused = changed == null
        ? unused
        : unused.where((u) => changed.contains(u.location.path)).toList();
    return AnalysisReport(
      version: '1.0',
      metrics: filteredRecords,
      unused: filteredUnused,
      explanations: buildExplanations(explainIds),
    )..attachAnalyzedFileCount(units.length);
  }

  Future<int> _emit(AnalysisReport report, CommonOptions options) async {
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
      if (ownsSink) {
        await sink.close();
      }
    }

    if (options.fatalWarnings && report.hasSeverityAtLeast(Severity.warning)) {
      return 1;
    }
    if (options.fatalStyle && report.hasSeverityAtLeast(Severity.info)) {
      return 1;
    }
    return ExitCode.success.code;
  }
}
