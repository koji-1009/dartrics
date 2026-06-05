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

  group('parseUnifiedZeroRanges', () {
    test('maps hunk headers to new-file line ranges', () {
      const diff = '''
diff --git a/lib/a.dart b/lib/a.dart
index 1111111..2222222 100644
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -10,2 +12,3 @@ void f() {
+x
+y
+z
@@ -30 +33 @@ void g() {
+w
''';
      final ranges = parseUnifiedZeroRanges(diff, cwd: '/repo');
      final key = ranges.keys.single;
      expect(key, endsWith('lib/a.dart'));
      expect(ranges[key], [(start: 12, end: 14), (start: 33, end: 33)]);
    });

    test('deletion-only hunks mark the line the removal abuts', () {
      const diff = '''
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -5,3 +4,0 @@ void f() {
-a
-b
-c
''';
      final ranges = parseUnifiedZeroRanges(diff, cwd: '/repo');
      expect(ranges.values.single, [(start: 4, end: 4)]);
    });

    test('deletion at the top of the file clamps to line 1', () {
      const diff = '''
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,2 +0,0 @@
-a
-b
''';
      final ranges = parseUnifiedZeroRanges(diff, cwd: '/repo');
      expect(ranges.values.single, [(start: 1, end: 1)]);
    });

    test('tracks multiple files independently', () {
      const diff = '''
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1 +1,2 @@
+x
+y
--- a/lib/b.dart
+++ b/lib/b.dart
@@ -7 +9 @@
+z
''';
      final ranges = parseUnifiedZeroRanges(diff, cwd: '/repo');
      expect(ranges, hasLength(2));
      final a = ranges.keys.firstWhere((k) => k.endsWith('a.dart'));
      final b = ranges.keys.firstWhere((k) => k.endsWith('b.dart'));
      expect(ranges[a], [(start: 1, end: 2)]);
      expect(ranges[b], [(start: 9, end: 9)]);
    });

    test('skips lines that look like hunk headers but do not parse', () {
      // Real git never emits these, but the parser takes arbitrary
      // strings — a malformed header must not crash or mis-attribute.
      const diff = '''
--- a/lib/a.dart
+++ b/lib/a.dart
@@@ not a hunk header
@@ -1 +1 @@
+x
''';
      final ranges = parseUnifiedZeroRanges(diff, cwd: '/repo');
      expect(ranges.values.single, [(start: 1, end: 1)]);
    });

    test('ignores a /dev/null new side and hunks outside any file', () {
      // `--diff-filter=AMR` excludes deletions, so this is defensive —
      // a deleted file's hunks must not be attributed to anything.
      const diff = '''
@@ -1 +1 @@ stray hunk before any header
--- a/lib/gone.dart
+++ /dev/null
@@ -1,3 +0,0 @@
-a
-b
-c
''';
      expect(parseUnifiedZeroRanges(diff, cwd: '/repo'), isEmpty);
    });
  });

  test('changedDartLineRangesSince covers only the edited lines', () async {
    final dir = await _initRepo('git_diff_ranges_');
    addTearDown(() => dir.delete(recursive: true));

    await File('${dir.path}/two.dart').writeAsString('''
void alpha() {
  print('alpha');
}

void beta() {
  print('beta');
}
''');
    await _runGit(dir.path, ['add', '.']);
    await _runGit(dir.path, ['commit', '-m', 'init']);

    // Touch beta's body only (line 6).
    await File('${dir.path}/two.dart').writeAsString('''
void alpha() {
  print('alpha');
}

void beta() {
  print('beta!');
}
''');
    await _runGit(dir.path, ['add', '.']);
    await _runGit(dir.path, ['commit', '-m', 'edit beta']);

    final ranges = await changedDartLineRangesSince(
      'HEAD~1',
      workingDirectory: dir.path,
    );
    final key = ranges.keys.single;
    expect(key, endsWith('two.dart'));
    // Only the edited line falls in the range — alpha (lines 1-3) does
    // not intersect.
    expect(ranges[key], [(start: 6, end: 6)]);
  });

  test('changedDartLineRangesSince surfaces GitDiffException', () async {
    final dir = await Directory.systemTemp.createTemp('git_diff_ranges_bad_');
    addTearDown(() => dir.delete(recursive: true));
    await expectLater(
      changedDartLineRangesSince('main', workingDirectory: dir.path),
      throwsA(isA<GitDiffException>()),
    );
  });

  test(
    'changedDartLineRangesSince GitDiffException on ProcessException',
    () async {
      Future<ProcessResult> stubRunner(
        String executable,
        List<String> arguments, {
        String? workingDirectory,
      }) {
        throw const ProcessException('git', [], 'git not found', 127);
      }

      await expectLater(
        changedDartLineRangesSince('main', runner: stubRunner),
        throwsA(isA<GitDiffException>()),
      );
    },
  );
}
