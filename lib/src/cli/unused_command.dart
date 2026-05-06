import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart';

import '../analyzer_runner.dart';
import '../config/config_loader.dart';
import '../models/analysis_report.dart';
import '../models/unused_declaration.dart';
import '../reporters/reporters.dart';
import '../unused/unused_detector.dart';
import 'common_options.dart';
import 'git_diff.dart';
import 'rules_command.dart';

/// `dartrics unused` — runs only the public-API reachability analysis.
class UnusedCommand extends Command<int> {
  UnusedCommand() {
    addCommonOptions(argParser);
  }

  @override
  String get name => 'unused';

  @override
  String get description => 'Detect unreachable public declarations.';

  @override
  Future<int> run() async {
    final options = CommonOptions.from(this);
    final config = await loadConfig(options.configPath);
    final paths = options.rest.isNotEmpty
        ? options.rest
        : <String>[options.root];
    final Set<String>? changed;
    try {
      changed = options.since == null
          ? null
          : (await changedDartFilesSince(options.since!)).toSet();
    } on GitDiffException catch (e) {
      stderr.writeln(e);
      return ExitCode.data.code;
    }
    final runner = AnalyzerRunner(roots: paths, exclude: config.exclude);
    final units = await runner.resolveAll();
    final unused = await const UnusedDetector().detect([
      for (final u in units)
        (path: u.path, unit: u.unit.unit, lineInfo: u.unit.lineInfo),
    ], config.unused);
    final List<UnusedDeclaration> filtered;
    if (changed == null) {
      filtered = unused;
    } else {
      final allow = changed;
      filtered = unused.where((u) => allow.contains(u.location.path)).toList();
    }
    final report = AnalysisReport(
      version: '1.0',
      metrics: const [],
      unused: filtered,
      explanations: buildExplanations(options.explain),
    )..attachAnalyzedFileCount(units.length);

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

    if (options.fatalWarnings && unused.isNotEmpty) return 1;
    return ExitCode.success.code;
  }
}
