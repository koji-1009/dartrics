import 'dart:io';

/// Static interception point for the CLI's stdout / stderr — same
/// shape as `FlutterError.onError`. Production binaries leave the
/// defaults (`dart:io.stdout` / `dart:io.stderr`) in place; tests
/// reassign the fields to in-memory sinks so the CLI's report payload,
/// error messages, and logger output do not interleave with the test
/// reporter's own streams during `coverage:test_with_coverage` runs.
///
/// The static-mutable shape is deliberate. `dart:io.stdout` / `stderr`
/// are not overridable, `IOOverrides` only covers the file system, and
/// a Zone-based redirect would run into broadcast-stream listeners
/// (the logger) that capture their attach-zone and outlive any single
/// test's `runZoned` scope. A plain static field reads "the current
/// sink" at write time, so listeners get the value in effect at the
/// moment the record fires — not the value bound when the listener
/// was attached. That keeps the lifecycle simple and makes the
/// override symmetric across all CLI write paths, logger included.
///
/// The save / set / restore boilerplate that goes with overriding the
/// fields lives in `test/cli/helpers.dart` (`withDartricsIO`) — it is
/// a test concern, not a production one.
abstract final class DartricsIO {
  /// Sink the CLI writes user-facing payload to (`--output -`, status
  /// summaries, version banner). Default: `dart:io.stdout`.
  static IOSink stdoutSink = stdout;

  /// Sink the CLI writes errors / warnings / dismissal-rejection
  /// notices / logger output to. Default: `dart:io.stderr`.
  static IOSink stderrSink = stderr;
}
