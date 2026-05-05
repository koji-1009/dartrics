import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart';

import '../analyzer_runner.dart';
import '../config/config.dart';
import '../config/config_loader.dart';
import '../metrics/metric_engine.dart';
import '../models/analysis_report.dart';
import '../reporters/reporters.dart';
import 'common_options.dart';

/// `dartrics analyze` — runs every metric calculator over the analysis root
/// and emits a report.
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
    final paths = options.rest.isNotEmpty ? options.rest : <String>[options.root];
    final report = await _analyze(paths, config);
    return _emit(report, options);
  }

  Future<AnalysisReport> _analyze(List<String> paths, Config config) async {
    final runner = AnalyzerRunner(roots: paths, exclude: config.exclude);
    final files = await runner.collectDartFiles();
    final engine = MetricEngine(thresholds: config.metricThresholds);
    final records = await engine.analyze(runner);
    return AnalysisReport(
      version: '1.0',
      metrics: records,
      unused: const [],
    )..attachAnalyzedFileCount(files.length);
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
