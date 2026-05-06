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
}
