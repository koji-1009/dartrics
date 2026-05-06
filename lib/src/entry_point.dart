import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart' show ExitCode;
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import 'cli/runner.dart';
import 'config/config_loader.dart';
import 'version.dart';

/// Process entrypoint. Wraps the [CommandRunner] in a guarded zone so
/// uncaught errors surface a deterministic, sysexits-aligned exit code
/// rather than crashing the VM:
///
/// - `ConfigException`            → `78 EX_CONFIG`
/// - `UsageException` (bad CLI)   → `64 EX_USAGE`
/// - any other uncaught error     → `70 EX_SOFTWARE`
Future<void> runApp(List<String> arguments) async {
  if (isVersionRequest(arguments)) {
    stdout.writeln('dartrics $dartricsVersion');
    exitCode = ExitCode.success.code;
    return;
  }
  await runZonedGuarded(() async {
    _setupLogging();
    try {
      final runner = buildCommandRunner();
      final code = await runner.run(arguments) ?? 0;
      exitCode = code;
    } on ConfigException catch (e) {
      stderr.writeln(e.toString());
      exitCode = ExitCode.config.code;
    } on UsageException catch (e) {
      stderr.writeln(e.toString());
      exitCode = ExitCode.usage.code;
    }
  }, handleUncaughtZoneError);
}

/// Surfaces an unhandled async error from the [runApp] zone as an
/// `EX_SOFTWARE` exit. Extracted as a top-level function so tests can
/// reach it without having to construct a guarded zone themselves.
@visibleForTesting
void handleUncaughtZoneError(Object error, StackTrace stack) {
  stderr.writeln('Unhandled error: $error\n$stack');
  exitCode = ExitCode.software.code;
}

/// Returns true when [arguments] requests the version flag at the top
/// level. Subcommand-scoped uses (e.g. `dartrics analyze --version`) are
/// intentionally not intercepted; subcommands don't define `--version`.
bool isVersionRequest(List<String> arguments) {
  for (final arg in arguments) {
    if (arg == '--') return false;
    if (arg == '--version') return true;
    // Stop scanning once we hit a subcommand name so `dartrics report
    // file --version` (hypothetical) wouldn't be hijacked.
    if (!arg.startsWith('-')) return false;
  }
  return false;
}

void _setupLogging() {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    final line = '${record.level.name}: ${record.message}';
    if (record.level >= Level.WARNING) {
      stderr.writeln(line);
    } else {
      stdout.writeln(line);
    }
  });
}
