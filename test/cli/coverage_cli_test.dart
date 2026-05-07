import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('coverage_cli_');
    await Directory('${dir.path}/lib').create();
    await File(
      '${dir.path}/pubspec.yaml',
    ).writeAsString('name: example\nenvironment:\n  sdk: ^3.10.0\n');
    await File('${dir.path}/lib/foo.dart').writeAsString('''
int branchy(int x) {
  if (x > 0) return 1;
  if (x < 0) return -1;
  return 0;
}
''');
  });

  tearDown(() => dir.delete(recursive: true));

  test('analyze --coverage attaches coverage to JSON violations', () async {
    final lcov = File('${dir.path}/cov.info');
    await lcov.writeAsString('''
SF:${dir.path}/lib/foo.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,1
DA:5,1
end_of_record
''');
    final config = File('${dir.path}/dartrics.yaml');
    await config.writeAsString('''
dartrics:
  metrics:
    cyclomatic-complexity: 1
''');
    final out = '${dir.path}/run.json';
    final code = await runQuietly([
      'analyze',
      '${dir.path}/lib',
      '--reporter',
      'json',
      '--output',
      out,
      '--coverage',
      lcov.path,
      '--snapshot',
      'none',
      '--config',
      config.path,
    ]);
    expect(code, 0);
    final body =
        jsonDecode(File(out).readAsStringSync()) as Map<String, Object?>;
    final metrics = (body['metrics']! as List).cast<Map<String, Object?>>();
    final fn = metrics.firstWhere(
      (m) => (m['scope']! as Map)['name'] == 'branchy',
    );
    final violations = (fn['violations']! as List).cast<Map<String, Object?>>();
    final v = violations.firstWhere(
      (v) => v['metric'] == 'cyclomatic-complexity',
    );
    expect(v['scopeCoverage'], 1.0);
    expect(v['complexityJustified'], isTrue);
    // Round 5 — engine surfaces which rule fired and the literal
    // threshold so consumers don't have to look it up. This lcov
    // ships only DA records, so the line-coverage fallback fires
    // (≥ 0.95 threshold).
    expect(v['complexityJustifiedBy'], 'line');
    expect(v['complexityJustifiedThreshold'], 0.95);
  });

  test('analyze --coverage none disables coverage attachment', () async {
    // Drop a default-path lcov; --coverage none should still skip it.
    final cov = Directory('${dir.path}/coverage')..createSync();
    await File('${cov.path}/lcov.info').writeAsString('''
SF:${dir.path}/lib/foo.dart
DA:1,1
end_of_record
''');
    final config = File('${dir.path}/dartrics.yaml');
    await config.writeAsString(
      'dartrics:\n  metrics:\n    cyclomatic-complexity: 1\n',
    );
    final out = '${dir.path}/run.json';
    final code = await runQuietly([
      'analyze',
      '${dir.path}/lib',
      '--reporter',
      'json',
      '--output',
      out,
      '--coverage',
      'none',
      '--snapshot',
      'none',
      '--root',
      dir.path,
      '--config',
      config.path,
    ]);
    expect(code, 0);
    final body =
        jsonDecode(File(out).readAsStringSync()) as Map<String, Object?>;
    final metrics = (body['metrics']! as List).cast<Map<String, Object?>>();
    final fn = metrics.firstWhere(
      (m) => (m['scope']! as Map)['name'] == 'branchy',
    );
    final violations = (fn['violations']! as List).cast<Map<String, Object?>>();
    expect(violations.first.containsKey('scopeCoverage'), isFalse);
  });

  test('analyze --coverage <missing> exits 65 EX_DATAERR', () async {
    final config = File('${dir.path}/dartrics.yaml');
    await config.writeAsString('dartrics:\n');
    final code = await runQuietly([
      'analyze',
      '${dir.path}/lib',
      '--reporter',
      'json',
      '--output',
      '${dir.path}/run.json',
      '--coverage',
      '${dir.path}/no-such-file.info',
      '--snapshot',
      'none',
      '--config',
      config.path,
    ]);
    expect(code, 65);
  });

  test('analyze --coverage on malformed file exits 65', () async {
    final lcov = File('${dir.path}/bad.info');
    await lcov.writeAsString('SF:/x\nDA:bogus\nend_of_record\n');
    final config = File('${dir.path}/dartrics.yaml');
    await config.writeAsString('dartrics:\n');
    final code = await runQuietly([
      'analyze',
      '${dir.path}/lib',
      '--reporter',
      'json',
      '--output',
      '${dir.path}/run.json',
      '--coverage',
      lcov.path,
      '--snapshot',
      'none',
      '--config',
      config.path,
    ]);
    expect(code, 65);
  });
}
