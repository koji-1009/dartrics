import 'dart:io';

import 'package:dartrics/src/coverage/coverage_loader.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('coverage_loader_');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test(
    'null cliValue + missing default file → null (no auto-discovery)',
    () async {
      final index = await loadCoverage(cliValue: null, root: dir.path);
      expect(index, isNull);
    },
  );

  test('null cliValue + present default file → loads it', () async {
    final cov = Directory('${dir.path}/coverage')..createSync();
    await File('${cov.path}/lcov.info')
        .writeAsString('SF:/x\nDA:1,1\nend_of_record\n');
    final index = await loadCoverage(cliValue: null, root: dir.path);
    expect(index, isNotNull);
    expect(index!.forFile('/x'), isNotNull);
  });

  test('"none" disables coverage even when the default exists', () async {
    final cov = Directory('${dir.path}/coverage')..createSync();
    await File('${cov.path}/lcov.info').writeAsString('SF:/x\nend_of_record\n');
    expect(await loadCoverage(cliValue: 'none', root: dir.path), isNull);
    expect(await loadCoverage(cliValue: 'NONE', root: dir.path), isNull);
  });

  test(
    'explicit cliValue with missing file throws CoverageLoadException',
    () async {
      expect(
        () =>
            loadCoverage(cliValue: '${dir.path}/missing.info', root: dir.path),
        throwsA(isA<CoverageLoadException>()),
      );
    },
  );
}
