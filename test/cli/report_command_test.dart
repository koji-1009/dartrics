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

  test(
    'preserves stable id, coverage, and dismiss state when re-emitting',
    () async {
      // Field-for-field round-trip. Round 2-4 added id / coverage /
      // complexityJustified / dismiss-* to the JSON shape; the report
      // decoder used to drop them, so re-emitting through the AI / md /
      // SARIF reporters silently lost the AI-loop continuity data. This
      // pins the round-trip.
      final input = File('${dir.path}/full.json');
      await input.writeAsString(
        jsonEncode({
          'version': '1.0',
          'analyzedFiles': [
            {'path': '/proj/lib/x.dart', 'sha256': 'abc123'},
          ],
          'metrics': [
            {
              'file': '/proj/lib/x.dart',
              'scope': {'type': 'method', 'name': 'X.y', 'line': 7},
              'values': {'cyclomatic-complexity': 12},
              'violations': [
                {
                  'id': 'a3f1c4e9b2d70218',
                  'metric': 'cyclomatic-complexity',
                  'level': 'warning',
                  'threshold': 10,
                  'scopeCoverage': 0.91,
                  'scopeBranchCoverage': 0.78,
                  'complexityJustified': true,
                  'dismissed': true,
                  'dismissReason': 'load-bearing state machine',
                  'dismissedFrom': 'yaml',
                  'dismissedBy': 'claude-opus-4-7',
                  'dismissedAt': '2026-05-07T10:00:00.000Z',
                },
              ],
            },
          ],
          'unused': <Object>[],
        }),
      );
      // Re-emit as JSON so we can assert the round-trip exactly.
      final out = File('${dir.path}/round.json');
      final code = await buildCommandRunner().run([
        'report',
        input.path,
        '--reporter',
        'json',
        '--output',
        out.path,
        '--config',
        '${dir.path}/no.yaml',
      ]);
      expect(code, 0);
      final decoded =
          jsonDecode(await out.readAsString()) as Map<String, Object?>;
      expect(decoded['analyzedFiles'], isNotEmpty);
      final v =
          ((decoded['metrics']! as List).first as Map)['violations']! as List;
      final entry = v.first as Map<String, Object?>;
      expect(entry['id'], 'a3f1c4e9b2d70218');
      expect(entry['scopeCoverage'], 0.91);
      expect(entry['scopeBranchCoverage'], 0.78);
      expect(entry['complexityJustified'], isTrue);
      expect(entry['dismissed'], isTrue);
      expect(entry['dismissReason'], 'load-bearing state machine');
      expect(entry['dismissedBy'], 'claude-opus-4-7');
      expect(entry['dismissedFrom'], 'yaml');
      expect(entry['dismissedAt'], '2026-05-07T10:00:00.000Z');
    },
  );
}
