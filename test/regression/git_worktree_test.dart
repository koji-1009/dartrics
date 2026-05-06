import 'dart:io';

import 'package:dartrics/src/regression/git_worktree.dart';
import 'package:test/test.dart';

void main() {
  late Directory repo;

  setUp(() async {
    repo = await _initRepo('git_worktree_test_');
    await File('${repo.path}/file.txt').writeAsString('hello\n');
    await _runGit(repo.path, ['add', '.']);
    await _runGit(repo.path, ['commit', '-m', 'init']);
  });

  tearDown(() async {
    await repo.delete(recursive: true);
  });

  test('add() materialises a detached worktree at the given ref', () async {
    final wt = await GitWorktree.add(ref: 'HEAD', from: repo.path);
    addTearDown(wt.dispose);
    expect(File('${wt.path}/file.txt').existsSync(), isTrue);
    expect(wt.from, repo.path);
  });

  test('dispose() removes the worktree and is idempotent', () async {
    final wt = await GitWorktree.add(ref: 'HEAD', from: repo.path);
    await wt.dispose();
    expect(Directory(wt.path).existsSync(), isFalse);
    // Second dispose should be a no-op, not an exception.
    await wt.dispose();
  });

  test('add() throws GitWorktreeException on a bogus ref', () async {
    expect(
      () => GitWorktree.add(ref: 'definitely-not-a-ref', from: repo.path),
      throwsA(isA<GitWorktreeException>()),
    );
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
