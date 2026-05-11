import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart';

import '../analyzer_runner.dart';
import '../config/config.dart';
import '../config/config_loader.dart';
import '../models/analysis_report.dart';
import '../models/unused_declaration.dart';
import '../reporters/reporters.dart';
import '../unused/apply.dart';
import '../unused/resolved_reachability.dart';
import '../unused/unused_detector.dart';
import 'common_options.dart';
import 'git_diff.dart';
import 'io_sinks.dart';
import 'snapshot.dart';

/// `dartrics unused` — runs only the public-API reachability analysis.
class UnusedCommand extends Command<int> {
  UnusedCommand() {
    addIoOptions(argParser);
    addAnalysisOptions(argParser);
    argParser
      ..addFlag(
        'apply',
        help:
            'Delete every detected unused declaration from disk. '
            'Refuses to run on a dirty git tree (override with --force). '
            'Files under `test/` / `integration_test/` are excluded by '
            'default — pass --include-tests to include them. '
            'Imports left unused after deletion can be cleaned up '
            'separately with `dart fix --apply`.',
        negatable: false,
      )
      ..addFlag(
        'include-tests',
        help:
            'When combined with --apply, also delete unused declarations '
            'in files under `test/` or `integration_test/`. Without this '
            'flag the test tree is left alone.',
        negatable: false,
      )
      ..addFlag(
        'force',
        help:
            'When combined with --apply, run even on a dirty git tree. '
            'You usually want to commit or stash first so the deletions '
            'land in their own diff.',
        negatable: false,
      )
      ..addMultiOption(
        'filter',
        help:
            'Narrow the report to specific declaration kinds. Repeat or '
            'comma-separate (e.g. --filter method,field). Valid kinds: '
            'function, method, class, field, typedef, enum, extension. '
            '`enum` targets individual enum constants; enum type '
            'declarations are filtered with `class`. Defaults to every '
            'kind. CLI value overrides any `unused: { filter: [...] }` '
            'block in analysis_options.yaml.',
        splitCommas: true,
      );
  }

  @override
  String get name => 'unused';

  @override
  String get description => 'Detect unreachable public declarations.';

  @override
  Future<int> run() async {
    final io = IoOptions.from(this);
    final analysis = AnalysisOptions.from(this);
    final config = await loadConfig(analysis.configPath);
    final paths = io.rest.isNotEmpty ? io.rest : <String>[analysis.root];
    final unusedConfig = mergeUnusedFilterFromCli(
      base: config.unused,
      cliFilter: argResults!['filter'] as List<String>,
    );
    try {
      parseUnusedFilter(unusedConfig.filter);
    } on FormatException catch (e) {
      DartricsIO.stderrSink.writeln('dartrics unused: ${e.message}');
      return ExitCode.usage.code;
    }
    final Set<String>? changed;
    try {
      changed = analysis.since == null
          ? null
          : (await changedDartFilesSince(analysis.since!)).toSet();
    } on GitDiffException catch (e) {
      DartricsIO.stderrSink.writeln(e);
      return ExitCode.data.code;
    }
    final runner = AnalyzerRunner(
      roots: paths,
      exclude: config.exclude,
      concurrency: analysis.concurrency,
    );
    final units = await runner.resolveAll();
    final unused = await const UnusedDetector().detectResolved([
      for (final u in units) (path: u.path, unit: u.unit),
    ], unusedConfig);

    final hashes = hashFiles([
      for (final u in units) (path: u.path, content: u.unit.content),
    ]);
    final snapshotConfig = resolveSnapshotConfig(
      config.snapshot,
      analysis.snapshot,
    );
    final snapshotChanged = _maybeApplySnapshot(
      snapshotConfig: snapshotConfig,
      root: analysis.root,
      sinceActive: analysis.since != null,
      hashes: hashes,
    );
    final activeFilter = changed ?? snapshotChanged;
    final filtered = _filterUnused(unused, activeFilter);
    final report = AnalysisReport(
      version: '1.0',
      metrics: const [],
      unused: filtered,
      analyzedFiles: hashes,
      explanations: const [],
      snapshotMode: snapshotConfig.mode.name,
      changedFileCount: activeFilter?.length,
    )..attachAnalyzedFileCount(units.length);

    await _emit(report, io);

    final applyExit = await _maybeApply(analysis, filtered);
    if (applyExit != null) return applyExit;

    if (analysis.fatalWarnings && unused.isNotEmpty) return 1;
    return ExitCode.success.code;
  }

  /// Reads + writes the snapshot file when one is configured. Returns
  /// the set of paths whose hash changed since the previous run, or
  /// `null` when snapshots are disabled or `--since` is doing the
  /// filtering work instead. `--since` and snapshot diffs are mutually
  /// exclusive — see the matching note in `analyze_command.dart`.
  Set<String>? _maybeApplySnapshot({
    required SnapshotConfig snapshotConfig,
    required String root,
    required bool sinceActive,
    required List<AnalyzedFile> hashes,
  }) {
    final snapshotPath = snapshotPathFor(snapshotConfig, root);
    Set<String>? snapshotChanged;
    if (snapshotPath != null && !sinceActive) {
      snapshotChanged = Snapshot.read(snapshotPath).changedPaths(hashes);
    }
    if (snapshotPath != null) {
      writeSnapshot(snapshotPath, hashes);
    }
    return snapshotChanged;
  }

  List<UnusedDeclaration> _filterUnused(
    List<UnusedDeclaration> unused,
    Set<String>? allowed,
  ) {
    if (allowed == null) return unused;
    return unused.where((u) => allowed.contains(u.location.path)).toList();
  }

  Future<void> _emit(AnalysisReport report, IoOptions io) async {
    final reporter = pickReporter(io.reporter, limit: io.limit);
    final IOSink sink;
    final bool ownsSink;
    if (io.output == '-') {
      sink = DartricsIO.stdoutSink;
      ownsSink = false;
    } else {
      sink = File(io.output).openWrite();
      ownsSink = true;
    }
    try {
      reporter.report(report, sink);
    } finally {
      if (ownsSink) {
        await sink.close();
      }
    }
  }

  /// Runs the `--apply` deletion pass when requested. Returns a
  /// non-null exit code when the run should abort (dirty git tree
  /// without `--force`); `null` otherwise.
  Future<int?> _maybeApply(
    AnalysisOptions analysis,
    List<UnusedDeclaration> filtered,
  ) async {
    final applyMode = argResults!['apply'] as bool;
    if (!applyMode) return null;
    final force = argResults!['force'] as bool;
    final includeTests = argResults!['include-tests'] as bool;
    if (!force && !isGitTreeClean(analysis.root)) {
      DartricsIO.stderrSink.writeln(
        'dartrics unused: refusing to apply on a dirty git tree. '
        'Commit or stash first, or pass --force.',
      );
      return ExitCode.usage.code;
    }
    final outcomes = applyDeletions(filtered, includeTests: includeTests);
    DartricsIO.stderrSink.write(buildApplySummary(outcomes));
    return null;
  }
}

/// Formats the user-visible summary of an `--apply` run as a single
/// (multi-line) string, ending with a trailing newline. Extracted from
/// [UnusedCommand] so the formatting branches (unsupported / notFound
/// addenda) are unit-testable without spawning the CLI or capturing
/// stderr.
String buildApplySummary(List<ApplyResult> outcomes) {
  final byOutcome = <ApplyOutcome, int>{};
  for (final r in outcomes) {
    byOutcome.update(r.outcome, (n) => n + 1, ifAbsent: () => 1);
  }
  final deleted = byOutcome[ApplyOutcome.deleted] ?? 0;
  final unsupported = byOutcome[ApplyOutcome.unsupportedKind] ?? 0;
  final skippedTest = byOutcome[ApplyOutcome.skippedTest] ?? 0;
  final notFound = byOutcome[ApplyOutcome.notFound] ?? 0;
  final coupled = byOutcome[ApplyOutcome.coupledConstructorFormal] ?? 0;
  final buf = StringBuffer()
    ..writeln(
      'dartrics unused --apply: '
      'deleted $deleted, '
      'unsupported $unsupported, '
      'skipped (tests) $skippedTest, '
      'skipped (constructor formal coupling) $coupled, '
      'not found $notFound. '
      'Run `dart fix --apply` to clean up newly-unused imports.',
    );
  if (unsupported > 0) {
    buf.writeln(
      '  "unsupported" entries cannot be auto-deleted because removal '
      'would leave invalid Dart (currently: removing the last constant '
      'of an enum). Reported but left untouched on disk.',
    );
  }
  if (coupled > 0) {
    buf.writeln(
      '  "constructor formal coupling" entries name a field still '
      'referenced as `this.<name>` in a constructor of the enclosing '
      'class. Auto-deletion would leave a dangling initializing formal '
      '(and likely break every call site passing `<name>:`). Left '
      'untouched. Affected:',
    );
    for (final r in outcomes) {
      if (r.outcome != ApplyOutcome.coupledConstructorFormal) continue;
      final d = r.detail;
      if (d == null) continue;
      final ctors = d.coupledConstructors.isEmpty
          ? '(constructor name unavailable)'
          : d.coupledConstructors.join(', ');
      buf.writeln('    ${d.file}:${d.line}  ${d.name}  →  $ctors');
    }
  }
  if (notFound > 0) {
    buf.writeln(
      '  "not found" entries indicate the source changed between '
      "detect and apply, or the declaration's name/line shape isn't "
      'one `--apply` currently walks. Re-run `dartrics unused`.',
    );
  }
  return buf.toString();
}
