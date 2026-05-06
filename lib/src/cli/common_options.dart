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
    return CommonOptions(
      configPath: results['config'] as String,
      reporter: results['reporter'] as String,
      output: results['output'] as String,
      root: results['root'] as String,
      since: results['since'] as String?,
      explain: List<String>.from(results['explain'] as List<String>),
      snapshot: results['snapshot'] as String?,
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
  final bool fatalWarnings;
  final bool fatalStyle;
  final bool verbose;
  final List<String> rest;
}
