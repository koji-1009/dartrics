import 'dart:convert';
import 'dart:io';

import 'package:dartrics/src/cli/runner.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('report_cmd_');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('re-emits a saved JSON report into another format', () async {
    final input = File('${dir.path}/metrics.json');
    await input.writeAsString(
      jsonEncode({
        'version': '1.0',
        'metrics': [
          {
            'file': '/proj/lib/x.dart',
            'scope': {'type': 'method', 'name': 'X.y', 'line': 7},
            'values': {'cyclomatic-complexity': 12},
            'violations': [
              {
                'metric': 'cyclomatic-complexity',
                'level': 'warning',
                'threshold': 10,
              },
            ],
          },
        ],
        'unused': [
          {
            'file': '/proj/lib/u.dart',
            'name': 'leftover',
            'kind': 'function',
            'line': 5,
          },
        ],
      }),
    );
    final out = File('${dir.path}/report.md');
    final code = await buildCommandRunner().run([
      'report',
      input.path,
      '--reporter',
      'md',
      '--output',
      out.path,
      '--config',
      '${dir.path}/no.yaml',
    ]);
    expect(code, 0);
    final body = await out.readAsString();
    expect(body, contains('cyclomatic-complexity'));
    expect(body, contains('leftover'));
  });

  test('exits 64 when no input file argument is given', () async {
    final code = await buildCommandRunner().run([
      'report',
      '--config',
      '${dir.path}/no.yaml',
    ]);
    expect(code, 64);
  });

  test('exits 65 when input file does not exist', () async {
    final code = await buildCommandRunner().run([
      'report',
      '${dir.path}/no-such-file.json',
      '--config',
      '${dir.path}/no.yaml',
    ]);
    expect(code, 65);
  });
}
