import 'dart:io';

import 'package:dartrics/src/cli/runner.dart';
import 'package:dartrics/src/cli/snapshot.dart';
import 'package:dartrics/src/config/config.dart';
import 'package:dartrics/src/models/analysis_report.dart';
import 'package:test/test.dart';

void main() {
  group('snapshotPathFor', () {
    test('cache mode resolves under .dart_tool/dartrics', () {
      expect(
        snapshotPathFor(const SnapshotConfig(), '/repo'),
        '/repo/.dart_tool/dartrics/snapshot.json',
      );
    });

    test('baseline mode lands at repo root', () {
      expect(
        snapshotPathFor(
          const SnapshotConfig(mode: SnapshotMode.baseline),
          '/repo',
        ),
        '/repo/dartrics-snapshot.json',
      );
    });

    test('none mode returns null', () {
      expect(
        snapshotPathFor(const SnapshotConfig(mode: SnapshotMode.none), '/repo'),
        isNull,
      );
    });

    test('explicit path overrides the per-mode default', () {
      expect(
        snapshotPathFor(const SnapshotConfig(path: 'custom.json'), '/repo'),
        '/repo/custom.json',
      );
    });
  });

  group('resolveSnapshotConfig', () {
    test('null CLI override keeps config untouched', () {
      const c = SnapshotConfig(mode: SnapshotMode.baseline);
      expect(resolveSnapshotConfig(c, null), same(c));
    });

    test('cache / baseline / none / off / custom path overrides win', () {
      expect(
        resolveSnapshotConfig(const SnapshotConfig(), 'cache').mode,
        SnapshotMode.cache,
      );
      expect(
        resolveSnapshotConfig(const SnapshotConfig(), 'baseline').mode,
        SnapshotMode.baseline,
      );
      expect(
        resolveSnapshotConfig(const SnapshotConfig(), 'none').mode,
        SnapshotMode.none,
      );
      expect(
        resolveSnapshotConfig(const SnapshotConfig(), 'off').mode,
        SnapshotMode.none,
      );
      final custom = resolveSnapshotConfig(
        const SnapshotConfig(),
        'custom/path.json',
      );
      expect(custom.path, 'custom/path.json');
    });
  });

  group('hashFiles + Snapshot', () {
    test('hashes are stable, sorted by path', () {
      final hashes = hashFiles([
        (path: 'b.dart', content: 'B'),
        (path: 'a.dart', content: 'A'),
      ]);
      expect(hashes.map((f) => f.path).toList(), ['a.dart', 'b.dart']);
      expect(hashes[0].sha256, isNot(equals(hashes[1].sha256)));
    });

    test('changedPaths surfaces only files whose hash differs', () {
      final initial = hashFiles([
        (path: 'a.dart', content: 'A'),
        (path: 'b.dart', content: 'B'),
      ]);
      final updated = hashFiles([
        (path: 'a.dart', content: 'A'),
        (path: 'b.dart', content: 'B-changed'),
      ]);
      final snap = Snapshot(
        entries: {for (final f in initial) f.path: f.sha256},
      );
      expect(snap.changedPaths(updated), {'b.dart'});
    });

    test('empty snapshot reports every file as changed', () {
      final hashes = hashFiles([(path: 'a.dart', content: 'A')]);
      expect(Snapshot(entries: const {}).changedPaths(hashes), {'a.dart'});
    });

    test('Snapshot.read returns empty for missing / malformed files', () async {
      final tmp = await Directory.systemTemp.createTemp('snap_read_');
      addTearDown(() => tmp.delete(recursive: true));
      // missing
      expect(Snapshot.read('${tmp.path}/no.json').entries, isEmpty);
      // malformed json
      await File('${tmp.path}/bad.json').writeAsString('not json');
      expect(
        () => Snapshot.read('${tmp.path}/bad.json'),
        throwsFormatException,
      );
      // valid but wrong shape
      await File('${tmp.path}/wrong.json').writeAsString('"string"');
      expect(Snapshot.read('${tmp.path}/wrong.json').entries, isEmpty);
      await File(
        '${tmp.path}/missing-list.json',
      ).writeAsString('{"version":"1"}');
      expect(Snapshot.read('${tmp.path}/missing-list.json').entries, isEmpty);
      // entry with non-string fields gets skipped
      await File('${tmp.path}/skipped-entry.json').writeAsString(
        '{"analyzedFiles":[{"path":1,"sha256":"x"},'
        '{"path":"a.dart","sha256":"abc"}]}',
      );
      expect(Snapshot.read('${tmp.path}/skipped-entry.json').entries, {
        'a.dart': 'abc',
      });
    });

    test('writeSnapshot creates parent dirs and round-trips', () async {
      final tmp = await Directory.systemTemp.createTemp('snap_write_');
      addTearDown(() => tmp.delete(recursive: true));
      final target = '${tmp.path}/.dart_tool/dartrics/snap.json';
      writeSnapshot(target, const [
        AnalyzedFile(path: 'a.dart', sha256: 'aaa'),
      ]);
      final loaded = Snapshot.read(target);
      expect(loaded.entries, {'a.dart': 'aaa'});
    });
  });

  group('analyze + snapshot end-to-end', () {
    test('second run with no changes produces zero metric records', () async {
      final dir = await Directory.systemTemp.createTemp('snap_e2e_');
      addTearDown(() => dir.delete(recursive: true));
      await Directory('${dir.path}/lib').create(recursive: true);
      await File(
        '${dir.path}/pubspec.yaml',
      ).writeAsString('name: example\nenvironment:\n  sdk: ^3.10.0\n');
      await File('${dir.path}/lib/a.dart').writeAsString('void a() {}\n');

      final out = '${dir.path}/run.json';
      // First run — populates the snapshot, emits everything.
      final code1 = await buildCommandRunner().run([
        'analyze',
        '${dir.path}/lib',
        '--reporter',
        'json',
        '--output',
        out,
        '--root',
        dir.path,
        '--config',
        '${dir.path}/no.yaml',
      ]);
      expect(code1, 0);

      // Second run — same content, snapshot hits, no records emitted.
      final code2 = await buildCommandRunner().run([
        'analyze',
        '${dir.path}/lib',
        '--reporter',
        'json',
        '--output',
        out,
        '--root',
        dir.path,
        '--config',
        '${dir.path}/no.yaml',
      ]);
      expect(code2, 0);
      final body = await File(out).readAsString();
      expect(body, contains('"metrics": []'));
    });

    test('--snapshot none disables the diff filter', () async {
      final dir = await Directory.systemTemp.createTemp('snap_off_');
      addTearDown(() => dir.delete(recursive: true));
      await Directory('${dir.path}/lib').create(recursive: true);
      await File('${dir.path}/lib/a.dart').writeAsString('void a() {}\n');
      final out = '${dir.path}/run.json';
      // Two consecutive runs with --snapshot none should both emit records.
      for (var i = 0; i < 2; i++) {
        final code = await buildCommandRunner().run([
          'analyze',
          '${dir.path}/lib',
          '--reporter',
          'json',
          '--output',
          out,
          '--snapshot',
          'none',
          '--config',
          '${dir.path}/no.yaml',
        ]);
        expect(code, 0);
      }
      final body = await File(out).readAsString();
      expect(body, contains('a.dart'));
    });
  });
}
