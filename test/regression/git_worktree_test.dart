import 'dart:io';

import 'package:dartrics/src/regression/git_worktree.dart';
import 'package:path/path.dart' as p;
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

  group('pruneStale()', () {
    test('removes a leftover dartrics worktree, directory included', () async {
      final wt = await GitWorktree.add(ref: 'HEAD', from: repo.path);
      await GitWorktree.pruneStale(from: repo.path);
      expect(Directory(wt.path).existsSync(), isFalse);
      expect(
        await _worktreeList(repo.path),
        isNot(contains(p.basename(wt.path))),
      );
    });

    test('leaves worktrees without the dartrics prefix alone', () async {
      final other = await Directory.systemTemp.createTemp('user_worktree_');
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
      await GitWorktree.pruneStale(from: repo.path);
      expect(await _worktreeList(repo.path), contains(p.basename(other.path)));
    });

    test('prunes a registration whose directory is already gone', () async {
      final wt = await GitWorktree.add(ref: 'HEAD', from: repo.path);
      await Directory(wt.path).delete(recursive: true);
      expect(await _worktreeList(repo.path), contains(p.basename(wt.path)));
      await GitWorktree.pruneStale(from: repo.path);
      expect(
        await _worktreeList(repo.path),
        isNot(contains(p.basename(wt.path))),
      );
    });

    test('is a no-op outside a git repository', () async {
      final dir = await Directory.systemTemp.createTemp('not_a_repo_');
      addTearDown(() => dir.delete(recursive: true));
      await GitWorktree.pruneStale(from: dir.path);
    });

    test('is a no-op on a nonexistent directory', () async {
      await GitWorktree.pruneStale(from: '${repo.path}/does-not-exist');
    });
  });
}

Future<String> _worktreeList(String repoPath) async {
  final r = await Process.run('git', [
    'worktree',
    'list',
    '--porcelain',
  ], workingDirectory: repoPath);
  return r.stdout as String;
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
