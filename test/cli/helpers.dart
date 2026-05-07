import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartrics/src/cli/io_sinks.dart';
import 'package:dartrics/src/cli/runner.dart';
import 'package:dartrics/src/entry_point.dart';

/// Restores [DartricsIO.stdoutSink] / [DartricsIO.stderrSink] to the
/// `dart:io` defaults. The static fields are the only meaningful
/// state on [DartricsIO], and the only legitimate non-default values
/// are test-supplied in-memory sinks — so "go back to defaults" is
/// the only restore semantic we ever need. Exposed so tests that
/// reassign [DartricsIO] outside [withDartricsIO] can clean up in
/// `tearDown`.
void resetDartricsIO() {
  DartricsIO.stdoutSink = stdout;
  DartricsIO.stderrSink = stderr;
}

/// Runs [body] with [DartricsIO.stdoutSink] / [DartricsIO.stderrSink]
/// reassigned to the supplied sinks. Either may be `null` to leave
/// that sink at its current value. On return — successful or thrown —
/// [resetDartricsIO] puts the `dart:io` defaults back, so the next
/// test never inherits a closed in-memory sink.
Future<T> withDartricsIO<T>(
  FutureOr<T> Function() body, {
  IOSink? stdoutSink,
  IOSink? stderrSink,
}) async {
  if (stdoutSink != null) DartricsIO.stdoutSink = stdoutSink;
  if (stderrSink != null) DartricsIO.stderrSink = stderrSink;
  try {
    return await body();
  } finally {
    resetDartricsIO();
  }
}

/// Drives [buildCommandRunner] with [args] inside a [withDartricsIO]
/// scope that captures stdout AND stderr into in-memory buffers.
/// Returns the exit code alongside both captured streams.
Future<({int? exitCode, String stdout, String stderr})> runCaptured(
  List<String> args,
) async {
  final outCtl = StreamController<List<int>>();
  final errCtl = StreamController<List<int>>();
  final outBuf = BytesBuilder();
  final errBuf = BytesBuilder();
  final drainOut = outCtl.stream.forEach(outBuf.add);
  final drainErr = errCtl.stream.forEach(errBuf.add);
  final outSink = IOSink(outCtl.sink);
  final errSink = IOSink(errCtl.sink);
  try {
    final code = await withDartricsIO(
      () => buildCommandRunner().run(args),
      stdoutSink: outSink,
      stderrSink: errSink,
    );
    await outSink.close();
    await errSink.close();
    await drainOut;
    await drainErr;
    return (
      exitCode: code,
      stdout: utf8.decode(outBuf.toBytes()),
      stderr: utf8.decode(errBuf.toBytes()),
    );
  } finally {
    if (!outCtl.isClosed) await outCtl.close();
    if (!errCtl.isClosed) await errCtl.close();
  }
}

/// Convenience wrapper around [runCaptured] for tests that only need
/// the exit code and want stdout / stderr silenced.
Future<int?> runQuietly(List<String> args) async {
  return (await runCaptured(args)).exitCode;
}

/// Drives [runApp] with [args] inside a [withDartricsIO] scope that
/// captures stdout AND stderr, and resets / reads back the global
/// [exitCode] so callers don't have to duplicate the boilerplate.
/// Returns the exit code `runApp` left in [exitCode].
Future<int> runAppQuietly(List<String> args) async {
  final outCtl = StreamController<List<int>>();
  final errCtl = StreamController<List<int>>();
  final drainOut = outCtl.stream.drain<void>();
  final drainErr = errCtl.stream.drain<void>();
  final outSink = IOSink(outCtl.sink);
  final errSink = IOSink(errCtl.sink);
  final savedExit = exitCode;
  exitCode = 0;
  try {
    await withDartricsIO(
      () => runApp(args),
      stdoutSink: outSink,
      stderrSink: errSink,
    );
    await outSink.close();
    await errSink.close();
    await drainOut;
    await drainErr;
    return exitCode;
  } finally {
    exitCode = savedExit;
    if (!outCtl.isClosed) await outCtl.close();
    if (!errCtl.isClosed) await errCtl.close();
  }
}
