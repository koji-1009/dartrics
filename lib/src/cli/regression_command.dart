import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart';
import 'package:path/path.dart' as p;

import '../analyzer_runner.dart';
import '../config/config.dart';
import '../config/config_loader.dart';
import '../metrics/metric_engine.dart';
import '../models/analysis_report.dart';
import '../models/regression_report.dart';
import '../models/source_location.dart';
import '../regression/git_worktree.dart';
import '../regression/regression_diff.dart';
import '../reporters/regression_reporter.dart';

/// `dartrics regression` — re-runs every metric on two states (a
/// historical git ref and either the current working tree or another
/// ref) and emits the per-scope, per-metric diff.
///
/// Designed for AI loops that just produced a refactor: ask dartrics
/// whether the refactor actually improved things, or whether it was
/// cosmetic.
class RegressionCommand extends Command<int> {
  RegressionCommand() {
    argParser
      ..addOption(
        'before',
        help: 'Git ref to use as the baseline. Defaults to HEAD~1.',
        defaultsTo: 'HEAD~1',
      )
      ..addOption(
        'after',
        help:
            'Git ref to compare against. When omitted, dartrics analyzes '
            'the current working tree (no worktree is created).',
      )
      ..addMultiOption(
        'metric',
        help:
            'Restrict the diff to the named metric ids (repeatable). '
            'Defaults to all metrics.',
        splitCommas: true,
      )
      ..addOption(
        'config',
        help: 'Path to the configuration file.',
        defaultsTo: 'analysis_options.yaml',
      )
      ..addOption(
        'reporter',
        help: 'Output format.',
        allowed: ['ai', 'json', 'md', 'console'],
        defaultsTo: 'ai',
      )
      ..addOption(
        'output',
        help: 'Output destination. Use "-" for stdout.',
        defaultsTo: '-',
      )
      ..addOption('root', help: 'Analysis root directory.', defaultsTo: '.');
  }

  @override
  String get name => 'regression';

  @override
  String get description =>
      'Compare metrics between two git states and surface the diff.';

  @override
  Future<int> run() async {
    final results = argResults!;
    final beforeRef = results['before'] as String;
    final afterRef = results['after'] as String?;
    final metricIds = (results['metric'] as List<String>).toSet();
    final configPath = results['config'] as String;
    final reporter = results['reporter'] as String;
    final output = results['output'] as String;
    final root = results['root'] as String;

    final config = await loadConfig(configPath);

    GitWorktree? beforeWt;
    GitWorktree? afterWt;
    try {
      beforeWt = await _addWorktree(beforeRef, root);
      final beforeRecords = _normalizePaths(
        await _runAnalyze(beforeWt.path, config),
        root: beforeWt.path,
      );

      final String afterPath;
      if (afterRef == null) {
        afterPath = root;
      } else {
        afterWt = await _addWorktree(afterRef, root);
        afterPath = afterWt.path;
      }
      final afterRecords = _normalizePaths(
        await _runAnalyze(afterPath, config),
        root: afterPath,
      );

      final regression = const RegressionDiff().compute(
        beforeLabel: beforeRef,
        afterLabel: afterRef ?? 'working tree',
        beforeRecords: beforeRecords,
        afterRecords: afterRecords,
        focusMetrics: metricIds.isEmpty ? null : metricIds,
      );

      await _emit(regression, reporter, output);
      return ExitCode.success.code;
    } on GitWorktreeException catch (e) {
      stderr.writeln(e);
      return ExitCode.data.code;
    } finally {
      await beforeWt?.dispose();
      await afterWt?.dispose();
    }
  }

  Future<GitWorktree> _addWorktree(String ref, String root) async {
    return GitWorktree.add(ref: ref, from: root);
  }

  Future<List<MetricRecord>> _runAnalyze(String root, Config config) async {
    final runner = AnalyzerRunner(roots: [root], exclude: config.exclude);
    final units = await runner.resolveAll();
    final engine = MetricEngine(
      thresholds: config.metricThresholds,
      flutter: config.flutter,
    );
    return engine.analyzeResolved(units);
  }

  /// Rewrites every record's file path to be relative to [root]. This
  /// is what makes scope identity stable between two worktrees that
  /// live at different absolute paths.
  List<MetricRecord> _normalizePaths(
    List<MetricRecord> records, {
    required String root,
  }) {
    final canonical = p.normalize(p.absolute(root));
    return [
      for (final r in records)
        MetricRecord(
          file: _relativize(r.file, canonical),
          scope: ScopeRef(
            kind: r.scope.kind,
            name: r.scope.name,
            location: SourceLocation(
              path: _relativize(r.scope.location.path, canonical),
              line: r.scope.location.line,
              column: r.scope.location.column,
            ),
          ),
          values: r.values,
          violations: r.violations,
        ),
    ];
  }

  String _relativize(String filePath, String root) {
    final canonical = p.normalize(p.absolute(filePath));
    if (p.isWithin(root, canonical)) return p.relative(canonical, from: root);
    return filePath;
  }

  Future<void> _emit(
    RegressionReport regression,
    String format,
    String output,
  ) async {
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
      const RegressionReporter().report(regression, sink, format);
    } finally {
      if (ownsSink) {
        await sink.close();
      }
    }
  }
}
