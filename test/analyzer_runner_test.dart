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
}
