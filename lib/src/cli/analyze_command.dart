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
import '../unused/resolved_reachability.dart';
import '../unused/unused_detector.dart';
import 'common_options.dart';
import 'git_diff.dart';
import 'io_sinks.dart';
import 'rules_command.dart';
import 'snapshot.dart';

/// `dartrics analyze` — runs every metric calculator and the unused
/// detector over the analysis root and emits a combined report.
class AnalyzeCommand extends Command<int> {
  AnalyzeCommand() {
    addCommonOptions(argParser);
    argParser.addMultiOption(
      'filter',
      help:
          'Narrow the unused-declaration report to specific declaration '
          'kinds (function, method, class, field, typedef, enum, '
          'extension). `enum` targets individual enum constants; enum '
          'type declarations are filtered with `class`. Repeat or '
          'comma-separate. Defaults to every kind. CLI value overrides '
          'any `unused: { filter: [...] }` block in analysis_options.yaml.',
      splitCommas: true,
    );
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
    final unusedConfig = mergeUnusedFilterFromCli(
      base: config.unused,
      cliFilter: argResults!['filter'] as List<String>,
    );
    try {
      parseUnusedFilter(unusedConfig.filter);
    } on FormatException catch (e) {
      DartricsIO.stderrSink.writeln('dartrics analyze: ${e.message}');
      return ExitCode.usage.code;
    }
    final Set<String>? changed;
    try {
      changed = await _resolveChangedFiles(options.since);
    } on GitDiffException catch (e) {
      DartricsIO.stderrSink.writeln(e);
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
      DartricsIO.stderrSink.writeln(e);
      return ExitCode.data.code;
    } on FormatException catch (e) {
      DartricsIO.stderrSink.writeln('coverage parse error: ${e.message}');
      return ExitCode.data.code;
    }
    final report = await _analyze((
      paths: paths,
      config: config,
      unusedConfig: unusedConfig,
      options: options,
      changed: changed,
      snapshotConfig: snapshotConfig,
      coverage: coverage,
    ));
    return _emit(report, options);
  }

  Future<Set<String>?> _resolveChangedFiles(String? since) async {
    if (since == null) return null;
    return (await changedDartFilesSince(since)).toSet();
  }

  Future<AnalysisReport> _analyze(_AnalyzeRequest req) async {
    final runner = AnalyzerRunner(
      roots: req.paths,
      exclude: req.config.exclude,
      concurrency: req.options.concurrency,
    );
    final units = await runner.resolveAll();
    final dismissals = _buildDismissalIndex(
      strictDismiss: req.options.strictDismiss,
      config: req.config.dismissals,
      root: req.options.root,
      units: units,
    );
    final engine = MetricEngine(
      thresholds: req.config.metricThresholds,
      flutter: req.config.flutter,
      test: req.config.test,
      coverage: req.coverage,
      dismissals: dismissals,
      dismissalConfig: req.config.dismissals,
      onDismissalRejection: _logDismissalRejection,
    );
    final records = engine.analyzeResolved(units);
    final unused = await const UnusedDetector().detectResolved([
      for (final u in units) (path: u.path, unit: u.unit),
    ], req.unusedConfig);

    final hashes = hashFiles([
      for (final u in units) (path: u.path, content: u.unit.content),
    ]);
    final snapshotPath = snapshotPathFor(req.snapshotConfig, req.options.root);
    Set<String>? snapshotChanged;
    if (snapshotPath != null && req.options.since == null) {
      snapshotChanged = Snapshot.read(snapshotPath).changedPaths(hashes);
    }
    if (snapshotPath != null) {
      writeSnapshot(snapshotPath, hashes);
    }

    // `--since` and snapshot diffs are mutually exclusive (snapshotChanged
    // is only computed when `--since` isn't active), so a coalescing read
    // is enough — no need to intersect.
    final allowed = req.changed ?? snapshotChanged;
    final filteredRecords = allowed == null
        ? records
        : records.where((r) => allowed.contains(r.file)).toList();
    final filteredUnused = allowed == null
        ? unused
        : unused.where((u) => allowed.contains(u.location.path)).toList();
    final resolvedExplainIds = req.options.autoExplain
        ? _autoExplainIds(filteredRecords)
        : const <String>[];
    final staleDismissals = _collectStaleDismissals(
      dismissals: dismissals,
      config: req.config.dismissals,
      analyzedPaths: {for (final u in units) u.path},
    );
    return AnalysisReport(
      version: '1.0',
      metrics: filteredRecords,
      unused: filteredUnused,
      analyzedFiles: hashes,
      explanations: buildExplanations(resolvedExplainIds),
      staleDismissals: staleDismissals,
      snapshotMode: req.snapshotConfig.mode.name,
      changedFileCount: allowed?.length,
    )..attachAnalyzedFileCount(units.length);
  }

  /// Walks the dismissal index for entries that never matched a live
  /// violation in [analyzedPaths]. The path filter ensures dismissals
  /// for files that weren't measured this run (because of `--since` or
  /// snapshot filtering) don't get falsely flagged as stale — they
  /// just weren't measured. Returns an empty list when [config] has
  /// `warnStale: false`, when dismissals are disabled, or when
  /// `--strict-dismiss` produced an empty index.
  List<StaleDismissal> _collectStaleDismissals({
    required DismissalIndex dismissals,
    required DismissalConfig config,
    required Set<String> analyzedPaths,
  }) {
    if (!config.warnStale || !config.enabled) return const [];
    if (dismissals.isEmpty) return const [];
    final stale = <StaleDismissal>[];
    for (final d in dismissals.staleEntries()) {
      if (!analyzedPaths.contains(d.file)) continue;
      DartricsIO.stderrSink.writeln(
        'dartrics: dismissal at ${d.file}::${d.scope} '
        '[${d.metricId}] never matched a live violation — likely '
        'stale, consider removing the entry.',
      );
      stale.add(
        StaleDismissal(
          file: d.file,
          scope: d.scope,
          metricId: d.metricId,
          source: d.source,
          reason: d.reason,
        ),
      );
    }
    return stale;
  }

  /// Returns the metric ids that fired at least one violation in
  /// [records], in first-seen order. Drives the auto-explain block on
  /// the AI / md / SARIF reporters.
  List<String> _autoExplainIds(List<MetricRecord> records) {
    final seen = <String>{};
    final out = <String>[];
    for (final r in records) {
      for (final v in r.violations) {
        if (seen.add(v.metricId)) out.add(v.metricId);
      }
    }
    return out;
  }

  Future<int> _emit(AnalysisReport report, CommonOptions options) async {
    final reporter = pickReporter(options.reporter, limit: options.limit);
    final IOSink sink;
    final bool ownsSink;
    if (options.output == '-') {
      sink = DartricsIO.stdoutSink;
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
    DartricsIO.stderrSink.writeln(
      'dartrics: dismissal rejected at ${d.file}::${d.scope} '
      '[${d.metricId}]: $reason',
    );
  }
}

/// Bundle of inputs `_analyze` needs. Collected into a single record so
/// the orchestrator's signature stays at one parameter even as the set
/// of inputs grows (coverage, snapshot, dismissal config, `--since`,
/// `--strict-dismiss`, `--auto-explain`, …). All fields are read-only.
typedef _AnalyzeRequest = ({
  List<String> paths,
  Config config,
  UnusedConfig unusedConfig,
  CommonOptions options,
  Set<String>? changed,
  SnapshotConfig snapshotConfig,
  CoverageIndex? coverage,
});
