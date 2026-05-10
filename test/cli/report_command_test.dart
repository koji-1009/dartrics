import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'helpers.dart';

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
    final code = await runQuietly([
      'report',
      input.path,
      '--reporter',
      'md',
      '--output',
      out.path,
    ]);
    expect(code, 0);
    final body = await out.readAsString();
    expect(body, contains('cyclomatic-complexity'));
    expect(body, contains('leftover'));
  });

  test('exits 64 when no input file argument is given', () async {
    final code = await runQuietly(['report']);
    expect(code, 64);
  });

  test('exits 65 when input file does not exist', () async {
    final code = await runQuietly(['report', '${dir.path}/no-such-file.json']);
    expect(code, 65);
  });

  test('throws FormatException when an `unused.kind` value is unknown', () {
    // Pin the FormatException branch in `_decodeUnused` — re-loading a
    // hand-edited or future-format report must surface the bad enum
    // string rather than crash with a less actionable null!. The CLI
    // entry point converts the throw into a `70 EX_SOFTWARE` exit;
    // here we drive the raw runner so the contract on the message is
    // visible.
    final input = File('${dir.path}/bad-kind.json');
    input.writeAsStringSync(
      jsonEncode({
        'version': '1.0',
        'metrics': <Object>[],
        'unused': [
          {
            'file': '/proj/lib/u.dart',
            'name': 'leftover',
            'kind': 'not-a-real-kind',
            'line': 5,
          },
        ],
      }),
    );
    expect(
      () => runQuietly([
        'report',
        input.path,
        '--reporter',
        'json',
        '--output',
        '${dir.path}/out.json',
      ]),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains('unused.kind'), contains('not-a-real-kind')),
        ),
      ),
    );
  });

  test(
    'preserves stable id, coverage, and dismiss state when re-emitting',
    () async {
      // Field-for-field round-trip. Pins that the JSON report's
      // id / coverage / complexityJustified / dismiss-* fields survive
      // re-emission through the AI / md / SARIF reporters.
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
                  'complexityJustifiedBy': 'branch',
                  'complexityJustifiedThreshold': 0.8,
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
      final code = await runQuietly([
        'report',
        input.path,
        '--reporter',
        'json',
        '--output',
        out.path,
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
      expect(entry['complexityJustifiedBy'], 'branch');
      expect(entry['complexityJustifiedThreshold'], 0.8);
      expect(entry['dismissed'], isTrue);
      expect(entry['dismissReason'], 'load-bearing state machine');
      expect(entry['dismissedBy'], 'claude-opus-4-7');
      expect(entry['dismissedFrom'], 'yaml');
      expect(entry['dismissedAt'], '2026-05-07T10:00:00.000Z');
    },
  );
}
