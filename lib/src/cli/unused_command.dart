import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart';

import '../analyzer_runner.dart';
import '../config/config_loader.dart';
import '../models/analysis_report.dart';
import '../models/unused_declaration.dart';
import '../reporters/reporters.dart';
import '../unused/apply.dart';
import '../unused/unused_detector.dart';
import 'common_options.dart';
import 'git_diff.dart';
import 'rules_command.dart';
import 'snapshot.dart';

/// `dartrics unused` — runs only the public-API reachability analysis.
class UnusedCommand extends Command<int> {
  UnusedCommand() {
    addCommonOptions(argParser);
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
      );
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
    final runner = AnalyzerRunner(
      roots: paths,
      exclude: config.exclude,
      concurrency: options.concurrency,
    );
    final units = await runner.resolveAll();
    final unused = await const UnusedDetector().detect([
      for (final u in units)
        (path: u.path, unit: u.unit.unit, lineInfo: u.unit.lineInfo),
    ], config.unused);

    final snapshotConfig = resolveSnapshotConfig(
      config.snapshot,
      options.snapshot,
    );
    final hashes = hashFiles([
      for (final u in units) (path: u.path, content: u.unit.content),
    ]);
    final snapshotPath = snapshotPathFor(snapshotConfig, options.root);
    Set<String>? snapshotChanged;
    if (snapshotPath != null && options.since == null) {
      snapshotChanged = Snapshot.read(snapshotPath).changedPaths(hashes);
    }
    if (snapshotPath != null) {
      writeSnapshot(snapshotPath, hashes);
    }

    // `--since` and snapshot diffs are mutually exclusive — see the
    // matching note in `analyze_command.dart`.
    final allowed = changed ?? snapshotChanged;
    final List<UnusedDeclaration> filtered;
    if (allowed == null) {
      filtered = unused;
    } else {
      filtered = unused
          .where((u) => allowed.contains(u.location.path))
          .toList();
    }
    final report = AnalysisReport(
      version: '1.0',
      metrics: const [],
      unused: filtered,
      analyzedFiles: hashes,
      explanations: buildExplanations(options.explain),
    )..attachAnalyzedFileCount(units.length);

    final reporter = pickReporter(options.reporter, limit: options.limit);
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

    final applyMode = argResults!['apply'] as bool;
    if (applyMode) {
      final force = argResults!['force'] as bool;
      final includeTests = argResults!['include-tests'] as bool;
      if (!force && !isGitTreeClean(options.root)) {
        stderr.writeln(
          'dartrics unused: refusing to apply on a dirty git tree. '
          'Commit or stash first, or pass --force.',
        );
        return ExitCode.usage.code;
      }
      final outcomes = applyDeletions(filtered, includeTests: includeTests);
      _printApplySummary(outcomes);
    }

    if (options.fatalWarnings && unused.isNotEmpty) return 1;
    return ExitCode.success.code;
  }

  void _printApplySummary(List<ApplyResult> outcomes) {
    stderr.write(buildApplySummary(outcomes));
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
  final buf = StringBuffer()
    ..writeln(
      'dartrics unused --apply: '
      'deleted $deleted, '
      'unsupported $unsupported, '
      'skipped (tests) $skippedTest, '
      'not found $notFound. '
      'Run `dart fix --apply` to clean up newly-unused imports.',
    );
  if (unsupported > 0) {
    buf.writeln(
      '  unsupported kinds (method / field / enumValue) need range '
      'computation relative to a containing declaration; left for a '
      'future pass.',
    );
  }
  if (notFound > 0) {
    buf.writeln(
      '  "not found" entries indicate the source changed between '
      "detect and apply, or the declaration's name/line shape isn't "
      'one this v1 of --apply walks. Re-run dartrics unused.',
    );
  }
  return buf.toString();
}
