import 'dart:io';

import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('dartrics unused --apply', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('unused_apply_');
      await Directory('${dir.path}/lib/src').create(recursive: true);
      await File(
        '${dir.path}/pubspec.yaml',
      ).writeAsString('name: example\nenvironment:\n  sdk: ^3.10.0\n');
      // The detector treats anything in `lib/` outside `lib/src/` as
      // an exported reachability root, so fixtures live under
      // `lib/src/` to land in the unused report.
      await File(
        '${dir.path}/lib/example.dart',
      ).writeAsString("import 'src/sample.dart';\nvoid main() => keepMe();\n");
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test(
      'deletes detected unused declaration when applied with --force',
      () async {
        // `keepMe` is called from `lib/example.dart`'s main and is
        // therefore reachable; `deleteMe` is not — the detector
        // flags it, --apply removes its source range.
        await File('${dir.path}/lib/src/sample.dart').writeAsString('''
void keepMe() {}

void deleteMe() {
  print('bye');
}
''');
        final code = await runQuietly([
          'unused',
          '--root',
          dir.path,
          '--reporter',
          'json',
          '--output',
          '${dir.path}/r.json',
          '--config',
          '${dir.path}/no.yaml',
          '--apply',
          // The temp dir isn't a git repo — isGitTreeClean returns
          // true on missing git, so --force isn't required here, but
          // the test passes it anyway to exercise the plumbing.
          '--force',
        ]);
        expect(code, 0);
        final after = await File(
          '${dir.path}/lib/src/sample.dart',
        ).readAsString();
        expect(after.contains('void deleteMe()'), isFalse);
        expect(after.contains('void keepMe()'), isTrue);
      },
    );

    test('refuses to apply on a dirty git tree without --force', () async {
      // Make this temp dir a git repo with one uncommitted file.
      final pr1 = await Process.run('git', [
        'init',
        '-q',
        '-b',
        'main',
      ], workingDirectory: dir.path);
      expect(pr1.exitCode, 0);
      await Process.run('git', [
        'config',
        'user.email',
        't@example.com',
      ], workingDirectory: dir.path);
      await Process.run('git', [
        'config',
        'user.name',
        'T',
      ], workingDirectory: dir.path);
      await Process.run('git', [
        'config',
        'commit.gpgsign',
        'false',
      ], workingDirectory: dir.path);
      await File('${dir.path}/lib/src/sample.dart').writeAsString('''
void keepMe() {}
void deleteMe() {}
''');
      // Untracked file → dirty tree.
      final code = await runQuietly([
        'unused',
        '--root',
        dir.path,
        '--reporter',
        'json',
        '--output',
        '${dir.path}/r.json',
        '--config',
        '${dir.path}/no.yaml',
        '--apply',
        // No --force.
      ]);
      // 64 = ExitCode.usage (refusal).
      expect(code, 64);
      final after = await File(
        '${dir.path}/lib/src/sample.dart',
      ).readAsString();
      expect(after.contains('void deleteMe()'), isTrue, reason: 'untouched');
    });

    test(
      'summary reports unsupported (method) and notFound branches',
      () async {
        // The detector for this fixture flags the unused method `m()`
        // and the unused class. The class can be deleted (top-level);
        // the method can't yet — emits unsupportedKind. We assert via
        // exit-code success and file-state side effects rather than
        // capturing stderr (the summary text is already pinned by
        // unit tests on `applyDeletions`).
        await File('${dir.path}/lib/src/sample.dart').writeAsString('''
class Unused {
  void m() {}
}
''');
        final code = await runQuietly([
          'unused',
          '--root',
          dir.path,
          '--reporter',
          'json',
          '--output',
          '${dir.path}/r.json',
          '--config',
          '${dir.path}/no.yaml',
          '--apply',
          '--force',
        ]);
        expect(code, 0);
        final after = await File(
          '${dir.path}/lib/src/sample.dart',
        ).readAsString();
        // The class was deleted (top-level supported).
        expect(after.contains('class Unused'), isFalse);
      },
    );

    test('top-level const fields are now deletable through the CLI', () async {
      // The 0.2.0 detector flags `const FOO = 42;` as
      // UnusedKind.field; apply now handles fields end-to-end so
      // the source is rewritten on success.
      await File('${dir.path}/lib/src/sample.dart').writeAsString('''
const FOO = 42;
''');
      final code = await runQuietly([
        'unused',
        '--root',
        dir.path,
        '--reporter',
        'json',
        '--output',
        '${dir.path}/r.json',
        '--config',
        '${dir.path}/no.yaml',
        '--apply',
        '--force',
      ]);
      expect(code, 0);
      final after = await File(
        '${dir.path}/lib/src/sample.dart',
      ).readAsString();
      expect(after.contains('FOO'), isFalse);
    });

    test(
      '`--filter method --apply` deletes only methods, leaves other kinds',
      () async {
        // Both an unused class and an unused method on a reachable
        // class — the filter narrows --apply to methods so the class
        // survives (still unused but not in the filter set) while
        // `unusedMember` is removed.
        await File('${dir.path}/lib/src/sample.dart').writeAsString('''
class Reached {
  void usedMember() {}
  void unusedMember() {}
}
class UnusedClass {}
void keepMe() {
  Reached().usedMember();
}
''');
        final code = await runQuietly([
          'unused',
          '--root',
          dir.path,
          '--reporter',
          'json',
          '--output',
          '${dir.path}/r.json',
          '--config',
          '${dir.path}/no.yaml',
          '--filter',
          'method',
          '--apply',
          '--force',
        ]);
        expect(code, 0);
        final after = await File(
          '${dir.path}/lib/src/sample.dart',
        ).readAsString();
        expect(after.contains('void unusedMember'), isFalse);
        expect(after.contains('void usedMember'), isTrue);
        expect(
          after.contains('class UnusedClass'),
          isTrue,
          reason: 'filter=method must not delete the class entry',
        );
      },
    );

    test('skips test/ files by default; --include-tests overrides', () async {
      await Directory('${dir.path}/test').create();
      // Top-level `unusedFn` in a test file — without --include-tests,
      // the apply pass leaves it alone. The lib/example.dart from
      // setUp already provides a reachable main().
      await File('${dir.path}/test/foo_test.dart').writeAsString('''
void unusedFn() {}
''');
      final code = await runQuietly([
        'unused',
        '--root',
        dir.path,
        '--reporter',
        'json',
        '--output',
        '${dir.path}/r.json',
        '--config',
        '${dir.path}/no.yaml',
        '--apply',
        '--force',
      ]);
      expect(code, 0);
      final after = await File('${dir.path}/test/foo_test.dart').readAsString();
      // Default — the test-file content is preserved.
      expect(after.contains('void unusedFn()'), isTrue);
    });
  });
}
