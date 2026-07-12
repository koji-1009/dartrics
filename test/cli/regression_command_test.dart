import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late Directory repo;

  setUp(() async {
    repo = await _initRepo('regression_test_');
    await Directory('${repo.path}/lib').create();
    await File(
      '${repo.path}/pubspec.yaml',
    ).writeAsString('name: example\nenvironment:\n  sdk: ^3.10.0\n');
    await File('${repo.path}/lib/foo.dart').writeAsString('''
int f(int x) {
  if (x > 0) return 1;
  if (x < 0) return -1;
  return 0;
}
''');
    await _runGit(repo.path, ['add', '.']);
    await _runGit(repo.path, ['commit', '-m', 'init']);
  });

  tearDown(() async {
    await repo.delete(recursive: true);
  });

  test(
    'regression compares HEAD~1 against the working tree (default)',
    () async {
      // Modify the function to lower CC (drop one branch).
      await File('${repo.path}/lib/foo.dart').writeAsString('''
int f(int x) {
  if (x > 0) return 1;
  return 0;
}
''');
      await _runGit(repo.path, ['add', '.']);
      await _runGit(repo.path, ['commit', '-m', 'simplify']);

      final out = '${repo.path}/diff.json';
      final code = await runQuietly([
        'regression',
        '--root',
        repo.path,
        '--reporter',
        'json',
        '--output',
        out,
        '--config',
        '${repo.path}/no.yaml',
      ]);
      expect(code, 0);
      final body =
          jsonDecode(File(out).readAsStringSync()) as Map<String, Object?>;
      expect(body['before'], 'HEAD~1');
      expect(body['after'], 'working tree');
      final summary = body['summary']! as Map<String, Object?>;
      expect((summary['improved']! as int) >= 1, isTrue);
    },
  );

  test('regression with --root pointing at a sub-directory package compares '
      'the matching sub-tree on both sides', () async {
    // A package that lives in a sub-directory of the git repo. The
    // historical side must analyze `pkg/` within the worktree, not the
    // whole repo normalized against the repo root, or no scope key
    // lines up and `improved` collapses to 0. A distinct filename keeps
    // the root package's `lib/foo.dart` from masking the bug via a key
    // collision.
    await Directory('${repo.path}/pkg/lib').create(recursive: true);
    final bar = File('${repo.path}/pkg/lib/bar.dart');
    await bar.writeAsString('''
int g(int x) {
  if (x > 0) return 1;
  if (x < 0) return -1;
  return 0;
}
''');
    await _runGit(repo.path, ['add', '.']);
    await _runGit(repo.path, ['commit', '-m', 'add pkg']);
    await bar.writeAsString('''
int g(int x) {
  if (x > 0) return 1;
  return 0;
}
''');
    await _runGit(repo.path, ['add', '.']);
    await _runGit(repo.path, ['commit', '-m', 'simplify pkg']);

    final out = '${repo.path}/diff.json';
    final code = await runQuietly([
      'regression',
      '--root',
      '${repo.path}/pkg',
      '--reporter',
      'json',
      '--output',
      out,
      '--config',
      '${repo.path}/no.yaml',
    ]);
    expect(code, 0);
    final body =
        jsonDecode(File(out).readAsStringSync()) as Map<String, Object?>;
    final summary = body['summary']! as Map<String, Object?>;
    expect((summary['improved']! as int) >= 1, isTrue);
  });

  test('regression --metric filters to the named ids', () async {
    final code = await runQuietly([
      'regression',
      '--before',
      'HEAD',
      '--after',
      'HEAD',
      '--metric',
      'cyclomatic-complexity',
      '--root',
      repo.path,
      '--reporter',
      'json',
      '--output',
      '${repo.path}/diff.json',
      '--config',
      '${repo.path}/no.yaml',
    ]);
    expect(code, 0);
    final body =
        jsonDecode(File('${repo.path}/diff.json').readAsStringSync())
            as Map<String, Object?>;
    final changes = (body['changes']! as List<Object?>)
        .cast<Map<String, Object?>>();
    for (final c in changes) {
      expect(c['metric'], 'cyclomatic-complexity');
    }
  });

  test(
    'regression with --after compares two refs (no working-tree dep)',
    () async {
      await File('${repo.path}/lib/foo.dart').writeAsString('''
int f(int x) {
  return x > 0 ? 1 : 0;
}
''');
      await _runGit(repo.path, ['add', '.']);
      await _runGit(repo.path, ['commit', '-m', 'shrink']);

      final code = await runQuietly([
        'regression',
        '--before',
        'HEAD~1',
        '--after',
        'HEAD',
        '--root',
        repo.path,
        '--reporter',
        'console',
        '--output',
        '${repo.path}/diff.txt',
        '--config',
        '${repo.path}/no.yaml',
      ]);
      expect(code, 0);
      expect(
        File('${repo.path}/diff.txt').readAsStringSync(),
        contains('regression: HEAD~1 -> HEAD'),
      );
    },
  );

  test('regression exits 65 on a bogus before-ref', () async {
    final code = await runQuietly([
      'regression',
      '--before',
      'bogus-ref',
      '--root',
      repo.path,
      '--reporter',
      'json',
      '--output',
      '${repo.path}/diff.json',
      '--config',
      '${repo.path}/no.yaml',
    ]);
    expect(code, 65);
  });

  test('regression md / ai reporters produce output without errors', () async {
    for (final fmt in const ['md', 'ai']) {
      final code = await runQuietly([
        'regression',
        '--before',
        'HEAD',
        '--after',
        'HEAD',
        '--root',
        repo.path,
        '--reporter',
        fmt,
        '--output',
        '${repo.path}/diff.$fmt',
        '--config',
        '${repo.path}/no.yaml',
      ]);
      expect(code, 0, reason: 'reporter $fmt');
      expect(File('${repo.path}/diff.$fmt').existsSync(), isTrue);
    }
  });

  test('regression --before HEAD against an identical working tree reports '
      'all unchanged', () async {
    // Exercises both sides of scope identity: the per-file library
    // metrics (whose scope name is the file path and must survive
    // normalization across two mount points) and a class-level CBO edge
    // that only exists when the `package:` import resolves — which the
    // historical worktree can't do without the seeded package config.
    await File('${repo.path}/lib/a.dart').writeAsString('''
class A {
  int one() => 1;
}
''');
    await File('${repo.path}/lib/b.dart').writeAsString('''
import 'package:example/a.dart';

class B {
  int useA() => A().one();
}
''');
    await _runGit(repo.path, ['add', '.']);
    await _runGit(repo.path, ['commit', '-m', 'package import']);
    // Simulates the working tree's `dart pub get` state; deliberately
    // not committed, so the mounted worktree starts without it.
    await _writePackageConfig(repo.path);

    final out = '${repo.path}/diff.json';
    final code = await runQuietly([
      'regression',
      '--before',
      'HEAD',
      '--root',
      repo.path,
      '--reporter',
      'json',
      '--output',
      out,
      '--config',
      '${repo.path}/no.yaml',
    ]);
    expect(code, 0);
    final body =
        jsonDecode(File(out).readAsStringSync()) as Map<String, Object?>;
    final summary = body['summary']! as Map<String, Object?>;
    expect(summary['improved'], 0);
    expect(summary['regressed'], 0);
    expect(summary['added'], 0);
    expect(summary['removed'], 0);
    expect(summary['neutralDelta'], 0);
  });

  test('regression removes stale dartrics worktrees at startup and spares '
      'foreign ones', () async {
    final stale = await Directory.systemTemp.createTemp('dartrics_worktree_');
    final other = await Directory.systemTemp.createTemp('user_worktree_');
    await _runGit(repo.path, [
      'worktree',
      'add',
      '--detach',
      stale.path,
      'HEAD',
    ]);
    await _runGit(repo.path, [
      'worktree',
      'add',
      '--detach',
      other.path,
      'HEAD',
    ]);
    addTearDown(() async {
      await Process.run('git', [
        'worktree',
        'remove',
        '--force',
        other.path,
      ], workingDirectory: repo.path);
    });

    final code = await runQuietly([
      'regression',
      '--before',
      'HEAD',
      '--after',
      'HEAD',
      '--root',
      repo.path,
      '--reporter',
      'json',
      '--output',
      '${repo.path}/diff.json',
      '--config',
      '${repo.path}/no.yaml',
    ]);
    expect(code, 0);
    expect(stale.existsSync(), isFalse);
    final list = await Process.run('git', [
      'worktree',
      'list',
      '--porcelain',
    ], workingDirectory: repo.path);
    final registered = list.stdout as String;
    expect(registered, isNot(contains(p.basename(stale.path))));
    expect(registered, contains(p.basename(other.path)));
  });

  test('regression --output - writes to stdout', () async {
    final r = await runCaptured([
      'regression',
      '--before',
      'HEAD',
      '--after',
      'HEAD',
      '--root',
      repo.path,
      '--reporter',
      'json',
      '--output',
      '-',
      '--config',
      '${repo.path}/no.yaml',
    ]);
    expect(r.exitCode, 0);
    expect(r.stdout, contains('"changes"'));
  });
}

Future<Directory> _initRepo(String prefix) async {
  final raw = await Directory.systemTemp.createTemp(prefix);
  final dir = Directory(raw.resolveSymbolicLinksSync());
  await _runGit(dir.path, ['init', '-b', 'main']);
  await _runGit(dir.path, ['config', 'user.email', 'test@example.com']);
  await _runGit(dir.path, ['config', 'user.name', 'Test']);
  await _runGit(dir.path, ['config', 'commit.gpgsign', 'false']);
  return dir;
}

Future<void> _runGit(String cwd, List<String> args) async {
  final r = await Process.run('git', args, workingDirectory: cwd);
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${r.stderr}');
  }
}

/// Hand-written equivalent of the `dart pub get` output for the
/// dependency-less `example` fixture package — deterministic and
/// offline, where spawning `pub` would be neither.
Future<void> _writePackageConfig(String root) async {
  final file = File('$root/.dart_tool/package_config.json');
  await file.parent.create(recursive: true);
  await file.writeAsString(
    jsonEncode({
      'configVersion': 2,
      'packages': [
        {
          'name': 'example',
          'rootUri': '../',
          'packageUri': 'lib/',
          'languageVersion': '3.0',
        },
      ],
    }),
  );
}
