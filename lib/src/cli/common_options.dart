import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:logging/logging.dart';

/// Adds the option set shared by every dartrics subcommand.
void addCommonOptions(ArgParser parser) {
  parser
    ..addOption(
      'config',
      help: 'Path to the configuration file.',
      defaultsTo: 'analysis_options.yaml',
    )
    ..addOption(
      'reporter',
      help: 'Output format.',
      allowed: ['console', 'json', 'md', 'ai', 'sarif'],
      defaultsTo: 'console',
    )
    ..addOption(
      'output',
      help: 'Output destination. Use "-" for stdout.',
      defaultsTo: '-',
    )
    ..addOption('root', help: 'Analysis root directory.', defaultsTo: '.')
    ..addOption(
      'since',
      help:
          'Restrict output to files changed since the given git ref '
          '(e.g. "main", "HEAD~1", "origin/main"). Resolution still uses '
          'the full project so cross-file analysis stays accurate.',
    )
    ..addMultiOption(
      'explain',
      help:
          'Inject the metric\'s rationale and refactor hints into the '
          'report. Repeat the flag (or use a comma-separated list) to '
          'include several metrics at once.',
      splitCommas: true,
    )
    ..addOption(
      'snapshot',
      help:
          'Override snapshot mode (cache | baseline | none) or supply a '
          'custom file path. Beats the analysis_options.yaml setting.',
    )
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
    )
    ..addFlag(
      'fatal-style',
      help: 'Exit non-zero if any style violation is reported.',
      negatable: false,
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      help: 'Enable verbose (FINE level) logging.',
      negatable: false,
    );
}

/// Captures the common option values resolved from a subcommand invocation.
class CommonOptions {
  CommonOptions({
    required this.configPath,
    required this.reporter,
    required this.output,
    required this.root,
    required this.since,
    required this.explain,
    required this.snapshot,
    required this.coverage,
    required this.strictDismiss,
    required this.concurrency,
    required this.fatalWarnings,
    required this.fatalStyle,
    required this.verbose,
    required this.rest,
  });

  factory CommonOptions.from(Command<int> command) {
    final results = command.argResults!;
    if (results['verbose'] as bool) {
      Logger.root.level = Level.FINE;
    }
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
    return CommonOptions(
      configPath: results['config'] as String,
      reporter: results['reporter'] as String,
      output: results['output'] as String,
      root: results['root'] as String,
      since: results['since'] as String?,
      explain: List<String>.from(results['explain'] as List<String>),
      snapshot: results['snapshot'] as String?,
      coverage: results['coverage'] as String?,
      strictDismiss: results['strict-dismiss'] as bool,
      concurrency: concurrency,
      fatalWarnings: results['fatal-warnings'] as bool,
      fatalStyle: results['fatal-style'] as bool,
      verbose: results['verbose'] as bool,
      rest: results.rest,
    );
  }

  final String configPath;
  final String reporter;
  final String output;
  final String root;
  final String? since;
  final List<String> explain;
  final String? snapshot;
  final String? coverage;
  final bool strictDismiss;

  /// `--concurrency` override. `null` ⇒ defaults to the host CPU count.
  final int? concurrency;
  final bool fatalWarnings;
  final bool fatalStyle;
  final bool verbose;
  final List<String> rest;
}
