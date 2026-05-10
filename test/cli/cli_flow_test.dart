import 'dart:convert';
import 'dart:io';

import 'package:dartrics/src/cli/runner.dart';
import 'package:test/test.dart';

import 'helpers.dart';

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
      final code = await runQuietly([
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

  test(
    'unused --filter narrows the report via the user-facing `class` alias',
    () async {
      final outFile = File('${dir.path}/u-filter.json');
      final code = await runQuietly([
        'unused',
        '${dir.path}/lib',
        '--reporter',
        'json',
        '--output',
        outFile.path,
        '--filter',
        'class',
        '--snapshot',
        'none',
        '--config',
        '${dir.path}/no.yaml',
      ]);
      expect(code, 0);
      final body =
          jsonDecode(outFile.readAsStringSync()) as Map<String, Object?>;
      final entries = body['unused']! as List<Object?>;
      // JSON output uses the same canonical spelling as `--filter`
      // so the user-facing names line up everywhere.
      for (final e in entries) {
        expect((e! as Map<String, Object?>)['kind'], 'class');
      }
      expect(
        entries.map((e) => (e! as Map<String, Object?>)['name']),
        contains('UnusedThing'),
      );
    },
  );

  test(
    'unused --filter rejects unknown kind names with usage exit code',
    () async {
      final code = await runQuietly([
        'unused',
        '${dir.path}/lib',
        '--filter',
        'nope',
        '--config',
        '${dir.path}/no.yaml',
      ]);
      // ExitCode.usage.code == 64
      expect(code, 64);
    },
  );

  test(
    'analyze --filter rejects unknown kind names with usage exit code',
    () async {
      final code = await runQuietly([
        'analyze',
        '${dir.path}/lib',
        '--filter',
        'nope',
        '--config',
        '${dir.path}/no.yaml',
      ]);
      expect(code, 64);
    },
  );

  test('unused --output writes to a file', () async {
    final out = File('${dir.path}/u.json');
    final code = await runQuietly([
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
    final code = await runQuietly([
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
      final code = await runQuietly([
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

  test('analyze with no positional arg falls back to --root', () async {
    final code = await runQuietly([
      'analyze',
      '--root',
      '${dir.path}/lib',
      '--reporter',
      'json',
      '--output',
      '${dir.path}/a-root.json',
      '--config',
      '${dir.path}/no.yaml',
    ]);
    expect(code, 0);
  });

  test('unused with no positional arg falls back to --root', () async {
    final code = await runQuietly([
      'unused',
      '--root',
      '${dir.path}/lib',
      '--reporter',
      'json',
      '--output',
      '${dir.path}/u-root.json',
      '--config',
      '${dir.path}/no.yaml',
    ]);
    expect(code, 0);
  });

  test(
    '--concurrency=4 produces the same report as the sequential default',
    () async {
      final outA = File('${dir.path}/cc-default.json');
      final codeA = await runQuietly([
        'analyze',
        '${dir.path}/lib',
        '--reporter',
        'json',
        '--output',
        outA.path,
        '--config',
        '${dir.path}/no.yaml',
        '--concurrency',
        '1',
        '--snapshot',
        'none',
      ]);
      final outB = File('${dir.path}/cc-parallel.json');
      final codeB = await runQuietly([
        'analyze',
        '${dir.path}/lib',
        '--reporter',
        'json',
        '--output',
        outB.path,
        '--config',
        '${dir.path}/no.yaml',
        '--concurrency',
        '4',
        '--snapshot',
        'none',
      ]);
      expect(codeA, 0);
      expect(codeB, 0);
      expect(outA.readAsStringSync(), outB.readAsStringSync());
    },
  );

  test('--concurrency rejects non-positive integers', () async {
    expect(
      () => buildCommandRunner().run([
        'analyze',
        '${dir.path}/lib',
        '--config',
        '${dir.path}/no.yaml',
        '--concurrency',
        '0',
      ]),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => buildCommandRunner().run([
        'analyze',
        '${dir.path}/lib',
        '--config',
        '${dir.path}/no.yaml',
        '--concurrency',
        'eight',
      ]),
      throwsA(isA<FormatException>()),
    );
  });

  test('--limit rejects non-positive integers', () async {
    expect(
      () => buildCommandRunner().run([
        'analyze',
        '${dir.path}/lib',
        '--config',
        '${dir.path}/no.yaml',
        '--limit',
        '0',
      ]),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => buildCommandRunner().run([
        'analyze',
        '${dir.path}/lib',
        '--config',
        '${dir.path}/no.yaml',
        '--limit',
        'lots',
      ]),
      throwsA(isA<FormatException>()),
    );
  });

  test('analyze --since filters output to git-changed dart files', () async {
    final repo = await _initGitRepo('cli_flow_since_');
    addTearDown(() => repo.delete(recursive: true));
    await Directory('${repo.path}/lib').create();
    await File(
      '${repo.path}/pubspec.yaml',
    ).writeAsString('name: example\nenvironment:\n  sdk: ^3.10.0\n');
    await File(
      '${repo.path}/lib/keep.dart',
    ).writeAsString('void keep() => print("hi");\n');
    await File(
      '${repo.path}/lib/touched.dart',
    ).writeAsString('void touched() => print("v1");\n');
    await _runGit(repo.path, ['add', '.']);
    await _runGit(repo.path, ['commit', '-m', 'init']);
    await File(
      '${repo.path}/lib/touched.dart',
    ).writeAsString('void touched(int x) {\n  if (x > 0) print(x);\n}\n');
    await _runGit(repo.path, ['add', '.']);
    await _runGit(repo.path, ['commit', '-m', 'modify']);

    final out = File('${repo.path}/out.json');
    final code = await Directory(repo.path).runIn(() async {
      return runQuietly([
        'analyze',
        '${repo.path}/lib',
        '--reporter',
        'json',
        '--output',
        out.path,
        '--since',
        'HEAD~1',
        '--config',
        '${repo.path}/no.yaml',
      ]);
    });
    expect(code, 0);
    final decoded =
        jsonDecode(await out.readAsString()) as Map<String, Object?>;
    final metricFiles = (decoded['metrics']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final files = metricFiles.map((m) => m['file']).toSet();
    expect(files.any((f) => f.toString().endsWith('touched.dart')), isTrue);
    expect(files.any((f) => f.toString().endsWith('keep.dart')), isFalse);
  });

  test('analyze --since exits 65 when ref is bogus', () async {
    final repo = await _initGitRepo('cli_flow_since_bad_');
    addTearDown(() => repo.delete(recursive: true));
    await File(
      '${repo.path}/pubspec.yaml',
    ).writeAsString('name: example\nenvironment:\n  sdk: ^3.10.0\n');
    await Directory('${repo.path}/lib').create();
    await File('${repo.path}/lib/x.dart').writeAsString('void x() {}\n');
    await _runGit(repo.path, ['add', '.']);
    await _runGit(repo.path, ['commit', '-m', 'init']);

    final code = await Directory(repo.path).runIn(() async {
      return runQuietly([
        'analyze',
        '${repo.path}/lib',
        '--reporter',
        'json',
        '--output',
        '${repo.path}/out.json',
        '--since',
        'bogus-ref',
        '--config',
        '${repo.path}/no.yaml',
      ]);
    });
    expect(code, 65);
  });

  test('unused --since filters declarations to changed files', () async {
    final repo = await _initGitRepo('cli_flow_unused_since_');
    addTearDown(() => repo.delete(recursive: true));
    await Directory('${repo.path}/lib/src').create(recursive: true);
    await File(
      '${repo.path}/pubspec.yaml',
    ).writeAsString('name: example\nenvironment:\n  sdk: ^3.10.0\n');
    await File('${repo.path}/lib/main.dart').writeAsString('void main() {}\n');
    await File(
      '${repo.path}/lib/src/touched.dart',
    ).writeAsString('void a() {}\n');
    await File(
      '${repo.path}/lib/src/untouched.dart',
    ).writeAsString('class B {}\n');
    await _runGit(repo.path, ['add', '.']);
    await _runGit(repo.path, ['commit', '-m', 'init']);
    await File(
      '${repo.path}/lib/src/touched.dart',
    ).writeAsString('void a() {} class NewlyUnused {}\n');
    await _runGit(repo.path, ['add', '.']);
    await _runGit(repo.path, ['commit', '-m', 'add unused']);

    final out = File('${repo.path}/u.json');
    final code = await Directory(repo.path).runIn(() async {
      return runQuietly([
        'unused',
        '${repo.path}/lib',
        '--reporter',
        'json',
        '--output',
        out.path,
        '--since',
        'HEAD~1',
        '--config',
        '${repo.path}/no.yaml',
      ]);
    });
    expect(code, 0);
    final decoded =
        jsonDecode(await out.readAsString()) as Map<String, Object?>;
    final unusedNames = (decoded['unused']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map((m) => m['name'])
        .toSet();
    expect(unusedNames, contains('NewlyUnused'));
    expect(unusedNames, isNot(contains('B')));
  });

  test('unused --since exits 65 when git fails', () async {
    final dir = await Directory.systemTemp.createTemp('cli_flow_unused_nogit_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/lib').create();
    await File(
      '${dir.path}/pubspec.yaml',
    ).writeAsString('name: example\nenvironment:\n  sdk: ^3.10.0\n');
    await File('${dir.path}/lib/x.dart').writeAsString('void x() {}\n');
    final code = await Directory(dir.path).runIn(() async {
      return runQuietly([
        'unused',
        '${dir.path}/lib',
        '--reporter',
        'json',
        '--output',
        '${dir.path}/u.json',
        '--since',
        'main',
        '--config',
        '${dir.path}/no.yaml',
      ]);
    });
    expect(code, 65);
  });

  test('analyze --output - prints to stdout (default sink path)', () async {
    final r = await runCaptured([
      'analyze',
      '${dir.path}/lib',
      '--reporter',
      'json',
      '--output',
      '-',
      '--config',
      '${dir.path}/no.yaml',
    ]);
    expect(r.exitCode, 0);
    expect(r.stdout, contains('"version"'));
  });

  test('report --output - prints to stdout (default sink path)', () async {
    final input = File('${dir.path}/in.json');
    await input.writeAsString('{"version":"1.0","metrics":[],"unused":[]}');
    final r = await runCaptured([
      'report',
      input.path,
      '--reporter',
      'json',
      '--output',
      '-',
      '--config',
      '${dir.path}/no.yaml',
    ]);
    expect(r.exitCode, 0);
    expect(r.stdout, contains('"version"'));
  });
}

Future<void> _runGit(String cwd, List<String> args) async {
  final r = await Process.run('git', args, workingDirectory: cwd);
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${r.stderr}');
  }
}

Future<Directory> _initGitRepo(String prefix) async {
  final raw = await Directory.systemTemp.createTemp(prefix);
  // macOS's `/var/folders` is a symlink to `/private/var/folders`. The
  // analyzer's file walker and `git diff` resolve the prefix differently,
  // so we hand both sides the symlink-resolved canonical path.
  final dir = Directory(raw.resolveSymbolicLinksSync());
  await _runGit(dir.path, ['init', '-b', 'main']);
  await _runGit(dir.path, ['config', 'user.email', 'test@example.com']);
  await _runGit(dir.path, ['config', 'user.name', 'Test']);
  await _runGit(dir.path, ['config', 'commit.gpgsign', 'false']);
  return dir;
}

extension on Directory {
  Future<T> runIn<T>(Future<T> Function() body) async {
    final previous = Directory.current;
    Directory.current = this;
    try {
      return await body();
    } finally {
      Directory.current = previous;
    }
  }
}
