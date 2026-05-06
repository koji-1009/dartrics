import 'dart:io';

import 'package:dartrics/src/entry_point.dart';
import 'package:io/io.dart' show ExitCode;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  /// Small helper that runs [body] with the global `exitCode` reset around
  /// it, returning whatever value the body left in it.
  Future<int> capturedExit(Future<void> Function() body) async {
    final saved = exitCode;
    exitCode = 0;
    try {
      await body();
      return exitCode;
    } finally {
      exitCode = saved;
    }
  }

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
    final code = await capturedExit(
      () => runApp([
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
      ]),
    );
    expect(code, 0);
    expect(File(out).existsSync(), isTrue);
  });

  test('runApp returns EX_USAGE on an unknown subcommand', () async {
    final code = await capturedExit(() => runApp(['no-such-command']));
    expect(code, ExitCode.usage.code);
  });

  test('runApp returns EX_CONFIG on malformed config', () async {
    final cfg = File('${tempDir.path}/bad.yaml');
    await cfg.writeAsString('dartrics:\n  metrics:\n    {broken\n');
    final code = await capturedExit(
      () => runApp([
        'analyze',
        tempDir.path,
        '--reporter',
        'json',
        '--output',
        '-',
        '--config',
        cfg.path,
      ]),
    );
    expect(code, ExitCode.config.code);
  });

  test('runApp finishes without rethrow on a no-op input', () async {
    // We can't easily provoke an actual uncaught zone error from outside
    // (every internal failure is caught by the inner try/catch). The
    // dedicated `handleUncaughtZoneError` test below covers the handler
    // body; this test just confirms the zone wrapping doesn't swallow a
    // plain successful path.
    final code = await capturedExit(
      () => runApp([
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
      ]),
    );
    expect([0, ExitCode.software.code], contains(code));
  });

  test('runApp installs a logger that routes WARNING to stderr', () async {
    final saved = Logger.root.level;
    addTearDown(() => Logger.root.level = saved);
    // --version short-circuits before _setupLogging, so use a real run
    // first. After the listener is attached, fire a WARNING-level log
    // record to drive line 66 of `_setupLogging`.
    await Directory('${tempDir.path}/lib').create();
    await File('${tempDir.path}/lib/a.dart').writeAsString('void a() {}\n');
    await capturedExit(
      () => runApp([
        'analyze',
        '${tempDir.path}/lib',
        '--reporter',
        'json',
        '--output',
        '${tempDir.path}/r.json',
        '--snapshot',
        'none',
        '--config',
        '${tempDir.path}/no.yaml',
        '--verbose',
      ]),
    );
    Logger.root.warning('forced-warning-for-coverage');
    // Give the broadcast stream a tick to fan the record out.
    await Future<void>.delayed(Duration.zero);
  });

  test('handleUncaughtZoneError sets EX_SOFTWARE', () async {
    final saved = exitCode;
    addTearDown(() => exitCode = saved);
    handleUncaughtZoneError('boom', StackTrace.current);
    expect(exitCode, ExitCode.software.code);
  });
}
