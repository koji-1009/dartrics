import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';

import 'cli/runner.dart';

/// Process entrypoint. Wraps the [CommandRunner] in a guarded zone so
/// uncaught errors surface a deterministic exit code (`70 EX_SOFTWARE`)
/// rather than crashing the VM.
Future<void> runApp(List<String> arguments) async {
  await runZonedGuarded(() async {
    _setupLogging();
    final runner = buildCommandRunner();
    final code = await runner.run(arguments) ?? 0;
    exitCode = code;
  }, (error, stack) {
    stderr.writeln('Unhandled error: $error\n$stack');
    exitCode = 70;
  });
}

void _setupLogging() {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    final sink = record.level >= Level.WARNING ? stderr : stdout;
    sink.writeln('${record.level.name}: ${record.message}');
  });
}
