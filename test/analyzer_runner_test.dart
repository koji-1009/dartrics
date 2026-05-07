import 'dart:io';

import 'package:dartrics/src/analyzer_runner.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('analyzer_runner_');
    await Directory('${dir.path}/lib').create();
    await File('${dir.path}/lib/a.dart').writeAsString('class A {}');
    await File('${dir.path}/lib/b.dart').writeAsString('class B {}');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('collectDartFiles walks recursively under a directory root', () async {
    final runner = AnalyzerRunner(roots: ['${dir.path}/lib']);
    final files = await runner.collectDartFiles();
    expect(files.length, 2);
    expect(files.any((p) => p.endsWith('a.dart')), isTrue);
    expect(files.any((p) => p.endsWith('b.dart')), isTrue);
  });

  test('collectDartFiles accepts a single file path as a root', () async {
    final runner = AnalyzerRunner(roots: ['${dir.path}/lib/a.dart']);
    final files = await runner.collectDartFiles();
    expect(files, hasLength(1));
    expect(files.first, endsWith('a.dart'));
  });

  test(
    'collectDartFiles skips paths that do not exist or are non-Dart',
    () async {
      final runner = AnalyzerRunner(roots: ['${dir.path}/missing.txt']);
      final files = await runner.collectDartFiles();
      expect(files, isEmpty);
    },
  );

  test('generated dart files are skipped by default', () async {
    await File('${dir.path}/lib/model.g.dart').writeAsString('// generated');
    await File(
      '${dir.path}/lib/model.freezed.dart',
    ).writeAsString('// generated');
    await File('${dir.path}/lib/router.gr.dart').writeAsString('// generated');
    await File('${dir.path}/lib/proto.pb.dart').writeAsString('// generated');
    final runner = AnalyzerRunner(roots: ['${dir.path}/lib']);
    final files = await runner.collectDartFiles();
    expect(files.any((p) => p.endsWith('.g.dart')), isFalse);
    expect(files.any((p) => p.endsWith('.freezed.dart')), isFalse);
    expect(files.any((p) => p.endsWith('.gr.dart')), isFalse);
    expect(files.any((p) => p.endsWith('.pb.dart')), isFalse);
    expect(files.any((p) => p.endsWith('a.dart')), isTrue);
  });

  test('includeGenerated: true brings generated files back in', () async {
    await File('${dir.path}/lib/model.g.dart').writeAsString('// generated');
    final runner = AnalyzerRunner(
      roots: ['${dir.path}/lib'],
      includeGenerated: true,
    );
    final files = await runner.collectDartFiles();
    expect(files.any((p) => p.endsWith('.g.dart')), isTrue);
  });

  test('exclude globs filter relative paths', () async {
    final runner = AnalyzerRunner(
      roots: ['${dir.path}/lib'],
      exclude: ['b.dart'],
    );
    final files = await runner.collectDartFiles();
    expect(files.any((p) => p.endsWith('b.dart')), isFalse);
  });

  group('concurrency', () {
    test('default clamps host CPU count to [1, 16]', () {
      // Whatever Platform.numberOfProcessors reports, the clamp must hold.
      final actual = AnalyzerRunner.defaultConcurrency();
      expect(actual, greaterThanOrEqualTo(1));
      expect(actual, lessThanOrEqualTo(16));
    });

    test('explicit concurrency=1 keeps the runner sequential', () async {
      // Resolves both files with the sequential branch — primarily a
      // coverage exercise; the assertion is that resolveAll returns
      // every collectable file in deterministic order.
      await File(
        '${dir.path}/pubspec.yaml',
      ).writeAsString('name: example\nenvironment:\n  sdk: ^3.10.0\n');
      final runner = AnalyzerRunner(roots: ['${dir.path}/lib'], concurrency: 1);
      final units = await runner.resolveAll();
      final paths = units.map((u) => u.path).toList();
      expect(paths.first.endsWith('a.dart'), isTrue);
      expect(paths.last.endsWith('b.dart'), isTrue);
    });

    test('parallel resolveAll preserves alphabetical ordering', () async {
      await File(
        '${dir.path}/pubspec.yaml',
      ).writeAsString('name: example\nenvironment:\n  sdk: ^3.10.0\n');
      final runner = AnalyzerRunner(roots: ['${dir.path}/lib'], concurrency: 4);
      final units = await runner.resolveAll();
      expect(
        units.map((u) => u.path).toList(),
        orderedEquals(units.map((u) => u.path).toList()..sort()),
      );
    });

    test('resolveAll returns const [] for empty file list', () async {
      final runner = AnalyzerRunner(roots: ['${dir.path}/empty']);
      final units = await runner.resolveAll();
      expect(units, isEmpty);
    });
  });

  group('nested sub-package fallout', () {
    test(
      'resolveAll skips files in a sub-pubspec excluded by analyzer.exclude',
      () async {
        // Outer package: dir/lib/{a,b}.dart with dir/pubspec.yaml plus an
        // analysis_options.yaml that excludes `sub/**` from analyzer.
        await File(
          '${dir.path}/pubspec.yaml',
        ).writeAsString('name: outer\nenvironment:\n  sdk: ^3.10.0\n');
        await File(
          '${dir.path}/analysis_options.yaml',
        ).writeAsString('analyzer:\n  exclude:\n    - sub/**\n');
        // Sub-package with its own pubspec under the excluded path.
        // `AnalysisContextCollection` honours the outer
        // `analyzer.exclude:` so it never builds a context for `sub/`,
        // and `contextFor` then throws `Bad state: Unable to find the
        // context …` on `sub/lib/c.dart`. dartrics's own file walker
        // sees the file (it does not consume `analyzer.exclude:`), so
        // before the catch in `resolve`, the whole run aborted on the
        // first stray sub-package fixture in the tree — exactly the
        // dogfood failure mode `tmp/sample/lib/violators.dart` produced
        // on the dartrics repo itself.
        await Directory('${dir.path}/sub/lib').create(recursive: true);
        await File(
          '${dir.path}/sub/pubspec.yaml',
        ).writeAsString('name: inner\nenvironment:\n  sdk: ^3.10.0\n');
        await File('${dir.path}/sub/lib/c.dart').writeAsString('class C {}\n');
        final runner = AnalyzerRunner(roots: [dir.path]);
        final units = await runner.resolveAll();
        // The outer package's two files still resolve; the sub-package
        // file is silently skipped instead of taking the run down.
        final paths = units.map((u) => u.path).toList();
        expect(paths.any((p) => p.endsWith('a.dart')), isTrue);
        expect(paths.any((p) => p.endsWith('b.dart')), isTrue);
        expect(paths.any((p) => p.endsWith('c.dart')), isFalse);
      },
    );
  });
}
