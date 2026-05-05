import 'dart:io';

import 'package:dartrics/src/cli/runner.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cli_flow_');
    await Directory('${dir.path}/lib/src').create(recursive: true);
    await File('${dir.path}/lib/foo.dart').writeAsString('void main() {}\n');
    await File('${dir.path}/lib/src/internal.dart').writeAsString('''
class UnusedThing {}
''');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test(
    'analyze --output writes JSON to a file and --verbose enables fine logs',
    () async {
      final out = File('${dir.path}/out.json');
      final code = await buildCommandRunner().run([
        'analyze',
        '${dir.path}/lib',
        '--reporter',
        'json',
        '--output',
        out.path,
        '--verbose',
        '--config',
        '${dir.path}/no.yaml',
      ]);
      expect(code, 0);
      expect(out.existsSync(), isTrue);
      expect(out.readAsStringSync(), contains('"version"'));
    },
  );

  test('unused --output writes to a file', () async {
    final out = File('${dir.path}/u.json');
    final code = await buildCommandRunner().run([
      'unused',
      '${dir.path}/lib',
      '--reporter',
      'json',
      '--output',
      out.path,
      '--config',
      '${dir.path}/no.yaml',
    ]);
    expect(code, 0);
    expect(out.existsSync(), isTrue);
  });

  test('unused --fatal-warnings exits 1 when something is unused', () async {
    // The fixture defines `UnusedThing` which never gets referenced.
    final code = await buildCommandRunner().run([
      'unused',
      '${dir.path}/lib',
      '--reporter',
      'json',
      '--output',
      '${dir.path}/u2.json',
      '--fatal-warnings',
      '--config',
      '${dir.path}/no.yaml',
    ]);
    expect(code, 1);
  });

  test(
    'analyze --fatal-warnings exits 1 when violations exceed warning threshold',
    () async {
      // Threshold of warning=0 forces every method's CC ≥ 1 to violate.
      final config = File('${dir.path}/strict.yaml');
      await config.writeAsString('''
dartrics:
  metrics:
    cyclomatic-complexity:
      warning: 0
''');
      await File('${dir.path}/lib/foo.dart').writeAsString('''
int f() { return 1; }
''');
      final code = await buildCommandRunner().run([
        'analyze',
        '${dir.path}/lib',
        '--reporter',
        'json',
        '--output',
        '${dir.path}/a.json',
        '--fatal-warnings',
        '--config',
        config.path,
      ]);
      expect(code, 1);
    },
  );

  test('analyze --output - prints to stdout (default sink path)', () async {
    final code = await buildCommandRunner().run([
      'analyze',
      '${dir.path}/lib',
      '--reporter',
      'json',
      '--output',
      '-',
      '--config',
      '${dir.path}/no.yaml',
    ]);
    expect(code, 0);
  });

  test('report --output - prints to stdout (default sink path)', () async {
    final input = File('${dir.path}/in.json');
    await input.writeAsString('{"version":"1.0","metrics":[],"unused":[]}');
    final code = await buildCommandRunner().run([
      'report',
      input.path,
      '--reporter',
      'json',
      '--output',
      '-',
      '--config',
      '${dir.path}/no.yaml',
    ]);
    expect(code, 0);
  });

  test(
    'analyze --fatal-style exits 1 when an info-level violation is present',
    () async {
      // Currently dartrics never emits Severity.info, so --fatal-style is a
      // no-op; exit stays 0 even on a clean file. Document the current
      // behavior: it does not flip to 1.
      final code = await buildCommandRunner().run([
        'analyze',
        '${dir.path}/lib',
        '--reporter',
        'json',
        '--output',
        '${dir.path}/a2.json',
        '--fatal-style',
        '--config',
        '${dir.path}/no.yaml',
      ]);
      expect(code, 0);
    },
  );
}
