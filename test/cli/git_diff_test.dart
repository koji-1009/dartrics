import 'dart:io';

import 'package:dartrics/src/cli/git_diff.dart';
import 'package:test/test.dart';

Future<void> _runGit(String dir, List<String> args) async {
  final r = await Process.run('git', args, workingDirectory: dir);
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${r.stderr}');
  }
}

Future<Directory> _initRepo(String prefix) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  await _runGit(dir.path, ['init', '-b', 'main']);
  await _runGit(dir.path, ['config', 'user.email', 'test@example.com']);
  await _runGit(dir.path, ['config', 'user.name', 'Test']);
  await _runGit(dir.path, ['config', 'commit.gpgsign', 'false']);
  return dir;
}

void main() {
  test('returns dart files modified between HEAD~1 and HEAD', () async {
    final dir = await _initRepo('git_diff_');
    addTearDown(() => dir.delete(recursive: true));

    await File('${dir.path}/a.dart').writeAsString('void a() {}');
    await File('${dir.path}/keep.txt').writeAsString('not dart');
    await _runGit(dir.path, ['add', '.']);
    await _runGit(dir.path, ['commit', '-m', 'init']);

    await File('${dir.path}/a.dart').writeAsString('void a() => print("hi");');
    await File('${dir.path}/b.dart').writeAsString('void b() {}');
    await File('${dir.path}/keep.txt').writeAsString('still not dart');
    await _runGit(dir.path, ['add', '.']);
    await _runGit(dir.path, ['commit', '-m', 'update']);

    final files = await changedDartFilesSince(
      'HEAD~1',
      workingDirectory: dir.path,
    );
    expect(files.any((p) => p.endsWith('a.dart')), isTrue);
    expect(files.any((p) => p.endsWith('b.dart')), isTrue);
    expect(files.any((p) => p.endsWith('keep.txt')), isFalse);
  });

  test('GitDiffException when the ref does not resolve', () async {
    final dir = await _initRepo('git_diff_bad_ref_');
    addTearDown(() => dir.delete(recursive: true));
    await File('${dir.path}/a.dart').writeAsString('void a() {}');
    await _runGit(dir.path, ['add', '.']);
    await _runGit(dir.path, ['commit', '-m', 'init']);

    await expectLater(
      changedDartFilesSince('definitely-not-a-ref', workingDirectory: dir.path),
      throwsA(isA<GitDiffException>()),
    );
  });

  test('GitDiffException when cwd is not a git repository', () async {
    final dir = await Directory.systemTemp.createTemp('git_diff_nonrepo_');
    addTearDown(() => dir.delete(recursive: true));
    await expectLater(
      changedDartFilesSince('main', workingDirectory: dir.path),
      throwsA(isA<GitDiffException>()),
    );
  });

  test('GitDiffException when the runner throws ProcessException', () async {
    Future<ProcessResult> stubRunner(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    }) {
      throw const ProcessException('git', [], 'git not found', 127);
    }

    await expectLater(
      changedDartFilesSince('main', runner: stubRunner),
      throwsA(isA<GitDiffException>()),
    );
  });
}
