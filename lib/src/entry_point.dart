import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart' show ExitCode;
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:stack_trace/stack_trace.dart';

import 'cli/io_sinks.dart';
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
    DartricsIO.stdoutSink.writeln('dartrics $dartricsVersion');
    exitCode = ExitCode.success.code;
    return;
  }
  await runZonedGuarded(() async {
    final logSub = setupLogging();
    try {
      try {
        final runner = buildCommandRunner();
        final code = await runner.run(arguments) ?? ExitCode.success.code;
        exitCode = code;
      } on ConfigException catch (e) {
        DartricsIO.stderrSink.writeln(e.toString());
        exitCode = ExitCode.config.code;
      } on UsageException catch (e) {
        DartricsIO.stderrSink.writeln(e.toString());
        exitCode = ExitCode.usage.code;
      }
    } finally {
      // Cancel the listener before returning so each `runApp` call owns
      // its own listener lifecycle. Without this, multi-run test suites
      // would stack listeners on `Logger.root` — every record would fire
      // N times, once per attached subscription.
      await logSub.cancel();
    }
  }, uncaughtZoneErrorHandler(arguments));
}

/// Builds the handler that surfaces an unhandled async error from the
/// [runApp] zone as an `EX_SOFTWARE` exit. The terse stack trace is
/// printed only when [arguments] carries `-v` / `--verbose`.
@visibleForTesting
void Function(Object, StackTrace) uncaughtZoneErrorHandler(
  List<String> arguments,
) {
  final verbose = arguments.contains('-v') || arguments.contains('--verbose');
  return (error, stack) {
    DartricsIO.stderrSink.writeln('Unhandled error: $error');
    if (verbose) {
      DartricsIO.stderrSink.writeln(Trace.from(stack).terse);
    }
    exitCode = ExitCode.software.code;
  };
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

/// Installs a logger listener that routes records to
/// [DartricsIO.stderrSink] via [routeLogRecord]. Returns the
/// subscription so [runApp] can cancel it on exit.
@visibleForTesting
StreamSubscription<LogRecord> setupLogging() {
  Logger.root.level = Level.INFO;
  return Logger.root.onRecord.listen(routeLogRecord);
}

/// Per-record dispatch for the listener installed by [setupLogging].
/// Routes every record to stderr so stdout carries only report
/// payload.
@visibleForTesting
void routeLogRecord(LogRecord record) {
  DartricsIO.stderrSink.writeln('${record.level.name}: ${record.message}');
}
