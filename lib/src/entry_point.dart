import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart' show ExitCode;
import 'package:logging/logging.dart';

import 'cli/runner.dart';
import 'config/config_loader.dart';

/// Process entrypoint. Wraps the [CommandRunner] in a guarded zone so
/// uncaught errors surface a deterministic, sysexits-aligned exit code
/// rather than crashing the VM:
///
/// - `ConfigException`            → `78 EX_CONFIG`
/// - `UsageException` (bad CLI)   → `64 EX_USAGE`
/// - any other uncaught error     → `70 EX_SOFTWARE`
Future<void> runApp(List<String> arguments) async {
  await runZonedGuarded(
    () async {
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
    },
    (error, stack) {
      stderr.writeln('Unhandled error: $error\n$stack');
      exitCode = ExitCode.software.code;
    },
  );
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
