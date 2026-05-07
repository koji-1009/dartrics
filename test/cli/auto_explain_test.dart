import 'dart:io';

import 'package:test/test.dart';

import 'helpers.dart';

/// Auto-explain smoke tests — making sure the rationale + refactor hints
/// for the metrics that fired at least one violation land in the report
/// without the user having to pass `--explain` for each one.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('auto_explain_');
    await Directory('${dir.path}/lib').create();
    await File('${dir.path}/pubspec.yaml').writeAsString('''
name: example
environment:
  sdk: ^3.10.0
''');
    await File('${dir.path}/lib/foo.dart').writeAsString('''
int branchy(int x) {
  if (x > 0) return 1;
  if (x < 0) return -1;
  if (x == 0) return 0;
  return 99;
}
''');
    await File('${dir.path}/strict.yaml').writeAsString('''
dartrics:
  metrics:
    cyclomatic-complexity:
      warning: 1
''');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('AI report ships rationale automatically when a metric fires', () async {
    final out = File('${dir.path}/r.yaml');
    final code = await runQuietly([
      'analyze',
      dir.path,
      '--reporter',
      'ai',
      '--output',
      out.path,
      '--config',
      '${dir.path}/strict.yaml',
      '--snapshot',
      'none',
    ]);
    expect(code, 0);
    final body = await out.readAsString();
    // The catalogue's rationale lives under the explain block; auto-explain
    // attaches the rationale for `cyclomatic-complexity` because it fired.
    expect(body, contains('explain:'));
    expect(body, contains('metric: cyclomatic-complexity'));
    expect(body, contains('rationale:'));
  });

  test('--no-auto-explain suppresses the explain block', () async {
    final out = File('${dir.path}/r.yaml');
    final code = await runQuietly([
      'analyze',
      dir.path,
      '--reporter',
      'ai',
      '--output',
      out.path,
      '--config',
      '${dir.path}/strict.yaml',
      '--snapshot',
      'none',
      '--no-auto-explain',
    ]);
    expect(code, 0);
    final body = await out.readAsString();
    expect(body, isNot(contains('explain:')));
  });

  test(
    '--explain takes priority + adds further metrics to the union',
    () async {
      final out = File('${dir.path}/r.yaml');
      final code = await runQuietly([
        'analyze',
        dir.path,
        '--reporter',
        'ai',
        '--output',
        out.path,
        '--config',
        '${dir.path}/strict.yaml',
        '--snapshot',
        'none',
        '--explain',
        'method-length',
      ]);
      expect(code, 0);
      final body = await out.readAsString();
      // Both the explicit (method-length) and the fired (cc) entries land.
      expect(body, contains('metric: method-length'));
      expect(body, contains('metric: cyclomatic-complexity'));
    },
  );
}
