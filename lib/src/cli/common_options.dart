import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:logging/logging.dart';

import '../config/config.dart';

/// Allowed values for `--reporter` across the analysis-shaped subcommands
/// (`analyze`, `unused`, `report`). The lighter subcommands (`rules`,
/// `regression`) declare their own allowed lists locally because they do
/// not support every reporter (`sarif` only makes sense for analyses
/// that produce per-file findings).
const List<String> analysisReporters = ['console', 'json', 'md', 'ai', 'sarif'];

// === IO options ===

/// Adds the IO option group: how the report is shaped and where it lands.
/// Used by every subcommand that emits a report, regardless of whether
/// that report comes from a fresh analysis or a re-emitted JSON file.
///
/// [reporters] is the allowed list for `--reporter`; defaults to
/// [analysisReporters]. [defaultReporter] is the value when `--reporter`
/// is omitted.
void addIoOptions(
  ArgParser parser, {
  List<String> reporters = analysisReporters,
  String defaultReporter = 'console',
}) {
  parser
    ..addOption(
      'reporter',
      help: 'Output format.',
      allowed: reporters,
      defaultsTo: defaultReporter,
    )
    ..addOption(
      'output',
      help: 'Output destination. Use "-" for stdout.',
      defaultsTo: '-',
    )
    ..addOption(
      'limit',
      help:
          'Cap the number of violations + unused entries shown by the '
          'ai and md reporters (after the priority sort). Useful when '
          'feeding the report into an AI loop with a fixed token '
          'budget. Truncated entries are summarised in the report.',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      help: 'Enable verbose (FINE level) logging.',
      negatable: false,
    );
}

/// Captures the IO option values resolved from a subcommand invocation.
/// Reading this also flips the global log level when `--verbose` is on,
/// so every command that uses [addIoOptions] must instantiate this once
/// at the top of its `run()` body.
class IoOptions {
  IoOptions({
    required this.reporter,
    required this.output,
    required this.limit,
    required this.rest,
  });

  factory IoOptions.from(Command<int> command) {
    final results = command.argResults!;
    if (results['verbose'] as bool) {
      Logger.root.level = Level.FINE;
    }
    final limitRaw = results['limit'] as String?;
    final int? limit;
    if (limitRaw == null) {
      limit = null;
    } else {
      final parsed = int.tryParse(limitRaw);
      if (parsed == null || parsed < 1) {
        throw FormatException(
          '--limit must be a positive integer (got "$limitRaw")',
        );
      }
      limit = parsed;
    }
    return IoOptions(
      reporter: results['reporter'] as String,
      output: results['output'] as String,
      limit: limit,
      rest: results.rest,
    );
  }

  final String reporter;
  final String output;

  /// `--limit <n>` override. `null` ⇒ no truncation; positive integer
  /// caps the number of violations + unused entries shown by the ai
  /// and md reporters.
  final int? limit;

  final List<String> rest;
}

// === Analysis options ===

/// Adds the analysis option group: how a fresh `package:analyzer` run is
/// configured. Used by every subcommand that re-runs analysis (`analyze`,
/// `unused`); skipped on subcommands that read a saved JSON (`report`)
/// or do not analyze code at all (`rules`, `manual`, `ai-loop`).
void addAnalysisOptions(ArgParser parser) {
  parser
    ..addOption(
      'config',
      help: 'Path to the configuration file.',
      defaultsTo: 'analysis_options.yaml',
    )
    ..addOption('root', help: 'Analysis root directory.', defaultsTo: '.')
    ..addOption(
      'since',
      help:
          'Restrict output to files changed since the given git ref '
          '(e.g. "main", "HEAD~1", "origin/main"). Resolution still uses '
          'the full project so cross-file analysis stays accurate.',
    )
    ..addOption(
      'snapshot',
      help:
          'Override snapshot mode (cache | baseline | none) or supply a '
          'custom file path. Beats the analysis_options.yaml setting.',
    )
    ..addOption(
      'concurrency',
      help:
          'Maximum number of files resolved in parallel. Defaults to '
          'the host CPU count clamped to 16.',
    )
    ..addFlag(
      'fatal-warnings',
      help: 'Exit non-zero if any warning is reported.',
      negatable: false,
    );
}

/// Captures the analysis option values resolved from a subcommand
/// invocation that called [addAnalysisOptions].
class AnalysisOptions {
  AnalysisOptions({
    required this.configPath,
    required this.root,
    required this.since,
    required this.snapshot,
    required this.concurrency,
    required this.fatalWarnings,
  });

  factory AnalysisOptions.from(Command<int> command) {
    final results = command.argResults!;
    final concurrencyRaw = results['concurrency'] as String?;
    final int? concurrency;
    if (concurrencyRaw == null) {
      concurrency = null;
    } else {
      final parsed = int.tryParse(concurrencyRaw);
      if (parsed == null || parsed < 1) {
        throw FormatException(
          '--concurrency must be a positive integer (got "$concurrencyRaw")',
        );
      }
      concurrency = parsed;
    }
    return AnalysisOptions(
      configPath: results['config'] as String,
      root: results['root'] as String,
      since: results['since'] as String?,
      snapshot: results['snapshot'] as String?,
      concurrency: concurrency,
      fatalWarnings: results['fatal-warnings'] as bool,
    );
  }

  final String configPath;
  final String root;
  final String? since;
  final String? snapshot;

  /// `--concurrency` override. `null` ⇒ defaults to the host CPU count.
  final int? concurrency;

  final bool fatalWarnings;
}

// === Metrics-reading options ===

/// Adds the option group for overlays that only metric-shaped reports
/// consume — coverage attachment and dismissal handling. Skipped on
/// subcommands like `unused` that emit no metric violations.
void addMetricsReadingOptions(ArgParser parser) {
  parser
    ..addOption(
      'coverage',
      help:
          'Path to an lcov.info file. Coverage data is attached to '
          'every emitted violation; high-coverage CC / Cognitive '
          'violations get a `complexityJustified` tag. Defaults to '
          'coverage/lcov.info when it exists; pass `none` to disable.',
    )
    ..addFlag(
      'strict-dismiss',
      help:
          'Ignore every dartrics:dismiss directive (comment + YAML) for '
          'this run. Intended for CI / final review where the operator '
          'wants to see what was triaged out.',
      negatable: false,
    );
}

/// Captures the metrics-reading option values resolved from a subcommand
/// that called [addMetricsReadingOptions].
class MetricsReadingOptions {
  const MetricsReadingOptions({
    required this.coverage,
    required this.strictDismiss,
  });

  factory MetricsReadingOptions.from(Command<int> command) {
    final results = command.argResults!;
    return MetricsReadingOptions(
      coverage: results['coverage'] as String?,
      strictDismiss: results['strict-dismiss'] as bool,
    );
  }

  final String? coverage;
  final bool strictDismiss;
}

/// Returns a copy of [base] with `filter` overridden by [cliFilter] when
/// the CLI supplied any value. An empty CLI list is treated as "no
/// override" so a user who omits `--filter` keeps the YAML setting.
UnusedConfig mergeUnusedFilterFromCli({
  required UnusedConfig base,
  required List<String> cliFilter,
}) {
  if (cliFilter.isEmpty) return base;
  return UnusedConfig(
    entryPoints: base.entryPoints,
    excludeExported: base.excludeExported,
    ignoreAnnotations: base.ignoreAnnotations,
    filter: cliFilter,
  );
}
