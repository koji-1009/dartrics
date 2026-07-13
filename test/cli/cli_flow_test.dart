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
    'unused: a `.g.dart` reference keeps the source declaration alive',
    () async {
      // Generators like riverpod_generator emit `.g.dart` files that
      // reference back into the source library. Dropping those files
      // from the analysis graph would strip the only edge into the
      // source declaration and produce a false positive — `dartrics
      // unused` runs with includeGenerated: true to keep the edge.
      await File('${dir.path}/lib/foo.dart').writeAsString('''
import 'wants.g.dart';
void main() {
  generatedEntry();
}
''');
      await File('${dir.path}/lib/wants.dart').writeAsString('''
void wantedByGenerated() {}
''');
      await File('${dir.path}/lib/wants.g.dart').writeAsString('''
import 'wants.dart';
void generatedEntry() {
  wantedByGenerated();
}
''');
      final out = File('${dir.path}/u-gen.json');
      final code = await runQuietly([
        'unused',
        '${dir.path}/lib',
        '--reporter',
        'json',
        '--output',
        out.path,
        '--snapshot',
        'none',
        '--config',
        '${dir.path}/no.yaml',
      ]);
      expect(code, 0);
      final body = jsonDecode(out.readAsStringSync()) as Map<String, Object?>;
      final names = (body['unused']! as List<Object?>)
          .map((e) => (e! as Map<String, Object?>)['name'])
          .toSet();
      expect(names, isNot(contains('wantedByGenerated')));
    },
  );

  test('analyze: a `.g.dart` reference keeps the source declaration alive '
      'while metrics/signals/analyzedFiles stay handwritten-only', () async {
    // `dartrics analyze` must see the same reachability edges as
    // `dartrics unused`: a `lib/src/` helper whose only caller lives
    // in a generated file is alive, not a false positive. Everything
    // else in the report keeps excluding generated files.
    await File('${dir.path}/lib/foo.dart').writeAsString('''
import 'src/gen.g.dart';
void main() {
  generatedEntry();
}
''');
    await File('${dir.path}/lib/src/helper.dart').writeAsString('''
void wantedByGenerated() {}
''');
    await File('${dir.path}/lib/src/gen.g.dart').writeAsString('''
import 'helper.dart';
void generatedEntry() {
  wantedByGenerated();
}
''');
    final out = File('${dir.path}/a-gen.json');
    final code = await runQuietly([
      'analyze',
      '${dir.path}/lib',
      '--reporter',
      'json',
      '--output',
      out.path,
      '--snapshot',
      'none',
      '--config',
      '${dir.path}/no.yaml',
    ]);
    expect(code, 0);
    final body = jsonDecode(out.readAsStringSync()) as Map<String, Object?>;
    final names = (body['unused']! as List<Object?>)
        .map((e) => (e! as Map<String, Object?>)['name'])
        .toSet();
    expect(names, isNot(contains('wantedByGenerated')));
    final metricFiles = ((body['metrics'] as List<Object?>?) ?? const []).map(
      (e) => (e! as Map<String, Object?>)['file']! as String,
    );
    expect(metricFiles.where((f) => f.endsWith('.g.dart')), isEmpty);
    final signalFiles = ((body['signals'] as List<Object?>?) ?? const []).map(
      (e) => (e! as Map<String, Object?>)['file']! as String,
    );
    expect(signalFiles, isNotEmpty);
    expect(signalFiles.where((f) => f.endsWith('.g.dart')), isEmpty);
    final analyzed = ((body['analyzedFiles'] as List<Object?>?) ?? const [])
        .map((e) => (e! as Map<String, Object?>)['path']! as String);
    expect(analyzed.where((f) => f.endsWith('.g.dart')), isEmpty);
  });

  test('unused: snapshot/analyzedFiles excludes `.g.dart`', () async {
    // Generated files participate in the reachability graph but must
    // stay out of the snapshot — a `dart run build_runner build` re-emit
    // would otherwise churn the snapshot and force re-analysis even
    // when no handwritten file changed.
    await File('${dir.path}/lib/g.g.dart').writeAsString('void g() {}\n');
    final out = File('${dir.path}/u-gen-files.json');
    final code = await runQuietly([
      'unused',
      '${dir.path}/lib',
      '--reporter',
      'json',
      '--output',
      out.path,
      '--snapshot',
      'none',
      '--config',
      '${dir.path}/no.yaml',
    ]);
    expect(code, 0);
    final body = jsonDecode(out.readAsStringSync()) as Map<String, Object?>;
    final analyzed = (body['analyzedFiles'] as List<Object?>?) ?? const [];
    for (final f in analyzed) {
      final path = (f! as Map<String, Object?>)['path']! as String;
      expect(path.endsWith('.g.dart'), isFalse);
    }
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

  test('analyze --since drops untouched scopes in a changed file', () async {
    // A file-granular filter re-surfaces functions the diff never
    // touched. Violations are intrinsic to the scope's text, so an
    // untouched function in a changed file must stay out of the report.
    final repo = await _initGitRepo('cli_flow_since_scope_');
    addTearDown(() => repo.delete(recursive: true));
    await Directory('${repo.path}/lib').create();
    await File(
      '${repo.path}/pubspec.yaml',
    ).writeAsString('name: example\nenvironment:\n  sdk: ^3.10.0\n');
    await File('${repo.path}/lib/two.dart').writeAsString('''
void alpha() {
  print('alpha');
}

void beta() {
  print('beta');
}
''');
    await _runGit(repo.path, ['add', '.']);
    await _runGit(repo.path, ['commit', '-m', 'init']);
    // Touch beta only; alpha's text is identical.
    await File('${repo.path}/lib/two.dart').writeAsString('''
void alpha() {
  print('alpha');
}

void beta() {
  print('beta!');
}
''');
    await _runGit(repo.path, ['add', '.']);
    await _runGit(repo.path, ['commit', '-m', 'edit beta']);

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
    final scopes = (decoded['metrics']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map((m) => (m['scope']! as Map<String, Object?>)['name'])
        .toSet();
    expect(scopes, contains('beta'));
    expect(scopes, isNot(contains('alpha')));
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
