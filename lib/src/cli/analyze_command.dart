import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:args/command_runner.dart';
import 'package:io/io.dart';
import 'package:path/path.dart' as p;

import '../analyzer_runner.dart';
import '../config/config.dart';
import '../config/config_loader.dart';
import '../coverage/coverage_loader.dart';
import '../coverage/lcov_reader.dart';
import '../dismiss/comment_parser.dart';
import '../dismiss/dismissal.dart';
import '../dismiss/dismissal_index.dart';
import '../dismiss/yaml_loader.dart';
import '../metrics/metric_engine.dart';
import '../models/analysis_report.dart';
import '../reporters/reporters.dart';
import '../unused/unused_detector.dart';
import 'common_options.dart';
import 'git_diff.dart';
import 'rules_command.dart';
import 'snapshot.dart';

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
    final snapshotConfig = resolveSnapshotConfig(
      config.snapshot,
      options.snapshot,
    );
    final CoverageIndex? coverage;
    try {
      coverage = await loadCoverage(
        cliValue: options.coverage,
        root: options.root,
      );
    } on CoverageLoadException catch (e) {
      stderr.writeln(e);
      return ExitCode.data.code;
    } on FormatException catch (e) {
      stderr.writeln('coverage parse error: ${e.message}');
      return ExitCode.data.code;
    }
    final report = await _analyze(
      paths,
      config,
      changed,
      options.explain,
      snapshotConfig,
      options.root,
      options.since != null,
      coverage,
      options.strictDismiss,
      options.concurrency,
    );
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
    SnapshotConfig snapshotConfig,
    String root,
    bool sinceActive,
    CoverageIndex? coverage,
    bool strictDismiss,
    int? concurrency,
  ) async {
    final runner = AnalyzerRunner(
      roots: paths,
      exclude: config.exclude,
      concurrency: concurrency,
    );
    final units = await runner.resolveAll();
    final dismissals = _buildDismissalIndex(
      strictDismiss: strictDismiss,
      config: config.dismissals,
      root: root,
      units: units,
    );
    final engine = MetricEngine(
      thresholds: config.metricThresholds,
      flutter: config.flutter,
      coverage: coverage,
      dismissals: dismissals,
      dismissalConfig: config.dismissals,
      onDismissalRejection: _logDismissalRejection,
    );
    final records = engine.analyzeResolved(units);
    final unused = await const UnusedDetector().detect([
      for (final u in units)
        (path: u.path, unit: u.unit.unit, lineInfo: u.unit.lineInfo),
    ], config.unused);

    final hashes = hashFiles([
      for (final u in units) (path: u.path, content: u.unit.content),
    ]);
    final snapshotPath = snapshotPathFor(snapshotConfig, root);
    Set<String>? snapshotChanged;
    if (snapshotPath != null && !sinceActive) {
      snapshotChanged = Snapshot.read(snapshotPath).changedPaths(hashes);
    }
    if (snapshotPath != null) {
      writeSnapshot(snapshotPath, hashes);
    }

    // `--since` and snapshot diffs are mutually exclusive (snapshotChanged
    // is only computed when `--since` isn't active), so a coalescing read
    // is enough — no need to intersect.
    final allowed = changed ?? snapshotChanged;
    final filteredRecords = allowed == null
        ? records
        : records.where((r) => allowed.contains(r.file)).toList();
    final filteredUnused = allowed == null
        ? unused
        : unused.where((u) => allowed.contains(u.location.path)).toList();
    return AnalysisReport(
      version: '1.0',
      metrics: filteredRecords,
      unused: filteredUnused,
      analyzedFiles: hashes,
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

  /// Combines the comment scanner and the YAML sidecar into a single
  /// lookup table the engine can hit per violation. Returns an empty
  /// index when [strictDismiss] is on or when neither source is
  /// enabled in [DismissalConfig].
  DismissalIndex _buildDismissalIndex({
    required bool strictDismiss,
    required DismissalConfig config,
    required String root,
    required List<({String path, ResolvedUnitResult unit})> units,
  }) {
    if (strictDismiss || !config.enabled) return DismissalIndex.empty();
    final comments = <Dismissal>[];
    if (config.commentSource) {
      for (final entry in units) {
        comments.addAll(
          scanCommentDismissals(
            path: entry.path,
            unit: entry.unit.unit,
            lineInfo: entry.unit.lineInfo,
          ),
        );
      }
    }
    final yaml = config.yamlSource
        ? loadYamlDismissals(_resolveYamlPath(config, root))
        : const <Dismissal>[];
    return DismissalIndex.build(comments: comments, yaml: yaml);
  }

  String _resolveYamlPath(DismissalConfig config, String root) {
    final base = config.yamlPath ?? defaultDismissalsYamlPath;
    if (p.isAbsolute(base)) return base;
    return p.join(root, base);
  }

  void _logDismissalRejection(Dismissal d, String reason) {
    stderr.writeln(
      'dartrics: dismissal rejected at ${d.file}::${d.scope} '
      '[${d.metricId}]: $reason',
    );
  }
}
