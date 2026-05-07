import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartrics/src/entry_point.dart';
import 'package:io/io.dart' show ExitCode;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late Directory tempDir;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('entry_point_');
  });
  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('runApp dispatches a successful command (exit 0)', () async {
    await Directory('${tempDir.path}/lib').create();
    await File('${tempDir.path}/lib/a.dart').writeAsString('void a() {}\n');
    final out = '${tempDir.path}/r.json';
    final code = await runAppQuietly([
      'analyze',
      '${tempDir.path}/lib',
      '--reporter',
      'json',
      '--output',
      out,
      '--snapshot',
      'none',
      '--config',
      '${tempDir.path}/no.yaml',
    ]);
    expect(code, 0);
    expect(File(out).existsSync(), isTrue);
  });

  test('runApp returns EX_USAGE on an unknown subcommand', () async {
    final code = await runAppQuietly(['no-such-command']);
    expect(code, ExitCode.usage.code);
  });

  test('runApp returns EX_CONFIG on malformed config', () async {
    final cfg = File('${tempDir.path}/bad.yaml');
    await cfg.writeAsString('dartrics:\n  metrics:\n    {broken\n');
    final code = await runAppQuietly([
      'analyze',
      tempDir.path,
      '--reporter',
      'json',
      '--output',
      '-',
      '--config',
      cfg.path,
    ]);
    expect(code, ExitCode.config.code);
  });

  test('runApp finishes without rethrow on a no-op input', () async {
    // We can't easily provoke an actual uncaught zone error from outside
    // (every internal failure is caught by the inner try/catch). The
    // dedicated `handleUncaughtZoneError` test below covers the handler
    // body; this test just confirms the zone wrapping doesn't swallow a
    // plain successful path.
    final code = await runAppQuietly([
      'analyze',
      '${tempDir.path}/no-such-path-12345',
      '--reporter',
      'json',
      '--output',
      '${tempDir.path}/x.json',
      '--snapshot',
      'none',
      '--config',
      '${tempDir.path}/no.yaml',
    ]);
    expect([0, ExitCode.software.code], contains(code));
  });

  group('routeLogRecord', () {
    test('WARNING (and above) goes to the resolved stderr sink', () async {
      final captured = await _captureRoute(
        () => routeLogRecord(LogRecord(Level.WARNING, 'msg', 'logger')),
      );
      expect(captured.stderr, equals('WARNING: msg\n'));
      expect(captured.stdout, isEmpty);
    });

    test('SEVERE also goes to stderr (>= WARNING boundary)', () async {
      final captured = await _captureRoute(
        () => routeLogRecord(LogRecord(Level.SEVERE, 'oops', 'logger')),
      );
      expect(captured.stderr, equals('SEVERE: oops\n'));
    });

    test('INFO and below go to the resolved stdout sink', () async {
      final captured = await _captureRoute(
        () => routeLogRecord(LogRecord(Level.INFO, 'note', 'logger')),
      );
      expect(captured.stdout, equals('INFO: note\n'));
      expect(captured.stderr, isEmpty);
    });
  });

  test('setupLogging installs a listener and tolerates re-installation', () {
    // Each call returns a fresh subscription; the previous one is left
    // attached to Logger.root unless the caller cancels it. `runApp`'s
    // try/finally is responsible for cancellation in production use.
    final saved = Logger.root.level;
    addTearDown(() => Logger.root.level = saved);
    final a = setupLogging();
    final b = setupLogging();
    addTearDown(a.cancel);
    addTearDown(b.cancel);
    expect(Logger.root.level, Level.INFO);
  });

  test('handleUncaughtZoneError sets EX_SOFTWARE', () async {
    final saved = exitCode;
    addTearDown(() => exitCode = saved);
    // The handler writes a stack-trace line to stderr; redirect into a
    // discard sink so it does not leak into the test reporter's stream.
    final ctl = StreamController<List<int>>();
    unawaited(ctl.stream.drain<void>());
    final sink = IOSink(ctl.sink);
    await withDartricsIO(
      () => handleUncaughtZoneError('boom', StackTrace.current),
      stderrSink: sink,
    );
    await sink.close();
    await ctl.close();
    expect(exitCode, ExitCode.software.code);
  });
}

/// Captures the stdout / stderr a route-log call routes to, so the
/// test can assert on the literal payload (not just that the code path
/// ran). Each call wires its own pair of sinks; [withDartricsIO] keeps
/// the override scoped to [body] and restores the previous values when
/// it returns, so the captured streams are unaffected by anything
/// published outside this helper.
Future<({String stdout, String stderr})> _captureRoute(
  void Function() body,
) async {
  final outCtl = StreamController<List<int>>();
  final errCtl = StreamController<List<int>>();
  final outBuf = BytesBuilder();
  final errBuf = BytesBuilder();
  final drainOut = outCtl.stream.forEach(outBuf.add);
  final drainErr = errCtl.stream.forEach(errBuf.add);
  final outSink = IOSink(outCtl.sink);
  final errSink = IOSink(errCtl.sink);
  await withDartricsIO(body, stdoutSink: outSink, stderrSink: errSink);
  await outSink.close();
  await errSink.close();
  await drainOut;
  await drainErr;
  await outCtl.close();
  await errCtl.close();
  return (
    stdout: utf8.decode(outBuf.toBytes()),
    stderr: utf8.decode(errBuf.toBytes()),
  );
}
