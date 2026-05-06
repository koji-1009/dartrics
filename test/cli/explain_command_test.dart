import 'dart:convert';
import 'dart:io';

import 'package:dartrics/src/cli/explain_command.dart';
import 'package:dartrics/src/cli/runner.dart';
import 'package:test/test.dart';

void main() {
  // Minimal JSON report fixture — one metric record with two violations,
  // shaped exactly as `dartrics analyze --reporter json` emits.
  Map<String, Object?> sampleReport({
    String idA = 'a3f1c4e9b2d70218',
    String idB = 'b7e2c5f10a3d4e21',
  }) {
    return {
      'version': '1.0',
      'metrics': [
        {
          'file': 'lib/parser.dart',
          'scope': {'type': 'method', 'name': 'Parser.parse', 'line': 42},
          'values': {'cognitive-complexity': 24, 'cyclomatic-complexity': 12},
          'violations': [
            {
              'id': idA,
              'metric': 'cognitive-complexity',
              'level': 'warning',
              'threshold': 15,
              'scopeCoverage': 0.91,
              'scopeBranchCoverage': 0.78,
            },
            {
              'id': idB,
              'metric': 'cyclomatic-complexity',
              'level': 'warning',
              'threshold': 10,
              'complexityJustified': true,
            },
          ],
        },
      ],
      'unused': [],
    };
  }

  group('findViolation', () {
    test('returns the matching ExplainHit with parent-record context', () {
      final hit = findViolation(sampleReport(), 'a3f1c4e9b2d70218');
      expect(hit, isNotNull);
      expect(hit!.file, 'lib/parser.dart');
      expect(hit.scopeName, 'Parser.parse');
      expect(hit.line, 42);
      expect(hit.metricId, 'cognitive-complexity');
      expect(hit.value, 24);
      expect(hit.threshold, 15);
      expect(hit.severity, 'warning');
      expect(hit.scopeCoverage, 0.91);
      expect(hit.scopeBranchCoverage, 0.78);
    });

    test('finds non-first violations within a record', () {
      final hit = findViolation(sampleReport(), 'b7e2c5f10a3d4e21');
      expect(hit, isNotNull);
      expect(hit!.metricId, 'cyclomatic-complexity');
      expect(hit.complexityJustified, isTrue);
    });

    test('returns null when no id matches', () {
      expect(findViolation(sampleReport(), 'nonexistent'), isNull);
    });

    test('tolerates malformed entries without crashing', () {
      final raw = {
        'metrics': [
          'not-a-map',
          {'no-violations-key': true},
          {'violations': 'not-a-list'},
        ],
      };
      expect(findViolation(raw, 'whatever'), isNull);
    });

    test('returns null when top-level shape is unexpected', () {
      expect(findViolation({}, 'x'), isNull);
      expect(findViolation({'metrics': 'not-a-list'}, 'x'), isNull);
    });
  });

  group('explain CLI', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('explain_cli_');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('emits AI-shaped YAML for a found violation', () async {
      final input = File('${dir.path}/report.json');
      await input.writeAsString(jsonEncode(sampleReport()));
      final output = '${dir.path}/explain.yaml';
      final code = await buildCommandRunner().run([
        'explain',
        'a3f1c4e9b2d70218',
        '--input',
        input.path,
        '--output',
        output,
      ]);
      expect(code, 0);
      final body = await File(output).readAsString();
      expect(body, contains('# dartrics explain v1'));
      expect(body, contains('id: a3f1c4e9b2d70218'));
      expect(body, contains('metric: cognitive-complexity'));
      expect(body, contains('value: 24'));
      expect(body, contains('threshold: 15'));
      expect(body, contains('coverage: 0.91'));
      // Auto-attached rationale + refactor hints from the catalogue.
      expect(body, contains('explain:'));
      expect(body, contains('rationale: |'));
      expect(body, contains('refactorHints:'));
    });

    test('--reporter json emits structured output', () async {
      final input = File('${dir.path}/report.json');
      await input.writeAsString(jsonEncode(sampleReport()));
      final output = '${dir.path}/explain.json';
      final code = await buildCommandRunner().run([
        'explain',
        'a3f1c4e9b2d70218',
        '--input',
        input.path,
        '--reporter',
        'json',
        '--output',
        output,
      ]);
      expect(code, 0);
      final decoded =
          jsonDecode(await File(output).readAsString()) as Map<String, Object?>;
      final violation = decoded['violation'] as Map<String, Object?>;
      expect(violation['id'], 'a3f1c4e9b2d70218');
      expect(violation['metric'], 'cognitive-complexity');
      final explain = decoded['explain'] as Map<String, Object?>;
      expect(explain['metric'], 'cognitive-complexity');
      expect(explain['polarity'], 'down');
    });

    test('exits 64 when id argument is missing', () async {
      final code = await buildCommandRunner().run(['explain']);
      expect(code, 64);
    });

    test('exits 65 when no violation matches the id', () async {
      final input = File('${dir.path}/report.json');
      await input.writeAsString(jsonEncode(sampleReport()));
      final code = await buildCommandRunner().run([
        'explain',
        'nonexistent-id',
        '--input',
        input.path,
      ]);
      expect(code, 65);
    });

    test('exits 65 when input file is invalid JSON', () async {
      final input = File('${dir.path}/bad.json');
      await input.writeAsString('not json at all');
      final code = await buildCommandRunner().run([
        'explain',
        'whatever',
        '--input',
        input.path,
      ]);
      expect(code, 65);
    });

    test('exits 65 when input file is missing', () async {
      final code = await buildCommandRunner().run([
        'explain',
        'whatever',
        '--input',
        '${dir.path}/does-not-exist.json',
      ]);
      expect(code, 65);
    });

    test('exits 65 when JSON top level is not an object', () async {
      final input = File('${dir.path}/array.json');
      await input.writeAsString('[]');
      final code = await buildCommandRunner().run([
        'explain',
        'x',
        '--input',
        input.path,
      ]);
      expect(code, 65);
    });

    test('--output - prints to stdout (default sink path)', () async {
      final input = File('${dir.path}/report.json');
      await input.writeAsString(jsonEncode(sampleReport()));
      final code = await buildCommandRunner().run([
        'explain',
        'a3f1c4e9b2d70218',
        '--input',
        input.path,
        '--output',
        '-',
      ]);
      expect(code, 0);
    });

    test(
      'renders complexityJustified, dismissalRejected, yaml-escape',
      () async {
        // The b-id violation has complexityJustified, plus we add a
        // dismissalRejected reason that contains a colon to exercise the
        // yaml-inline escape branch.
        final report = sampleReport();
        final metric =
            (report['metrics']! as List).first as Map<String, Object?>;
        final violations = metric['violations']! as List;
        final v = violations[1] as Map<String, Object?>;
        v['dismissalRejected'] = 'reason: too short (need >= 20)';
        final input = File('${dir.path}/rich.json');
        await input.writeAsString(jsonEncode(report));
        final output = '${dir.path}/rich.yaml';
        final code = await buildCommandRunner().run([
          'explain',
          'b7e2c5f10a3d4e21',
          '--input',
          input.path,
          '--output',
          output,
        ]);
        expect(code, 0);
        final body = await File(output).readAsString();
        expect(body, contains('complexityJustified: true'));
        expect(body, contains('dismissalRejected: '));
        expect(body, contains(r'reason: too short'));
      },
    );

    test('renders dismissed flag', () async {
      final report = sampleReport();
      final metric = (report['metrics']! as List).first as Map<String, Object?>;
      final violations = metric['violations']! as List;
      final v = violations[0] as Map<String, Object?>;
      v['dismissed'] = true;
      final input = File('${dir.path}/dismissed.json');
      await input.writeAsString(jsonEncode(report));
      final output = '${dir.path}/dismissed.yaml';
      final code = await buildCommandRunner().run([
        'explain',
        'a3f1c4e9b2d70218',
        '--input',
        input.path,
        '--output',
        output,
      ]);
      expect(code, 0);
      final body = await File(output).readAsString();
      expect(body, contains('dismissed: true'));
    });

    test('readReportBody reads from a synthetic stdin stream', () async {
      // Direct unit test against the readReportBody helper. The shell
      // pattern (`dartrics analyze --reporter json | dartrics explain
      // <id>`) routes the JSON through stdin in production; here we
      // pipe it through a Stream<List<int>> instead so the parent test
      // process — what coverage:test_with_coverage instruments — earns
      // the line.
      final body = await readReportBody(
        '-',
        stdinSource: Stream.value(utf8.encode(jsonEncode(sampleReport()))),
      );
      final hit = findViolation(
        jsonDecode(body) as Map<String, Object?>,
        'a3f1c4e9b2d70218',
      );
      expect(hit, isNotNull);
      expect(hit!.metricId, 'cognitive-complexity');
    });

    test('readReportBody reads from a file when input is a path', () async {
      final f = File('${dir.path}/path.json');
      await f.writeAsString(jsonEncode(sampleReport()));
      final body = await readReportBody(f.path);
      expect(body, contains('a3f1c4e9b2d70218'));
    });

    test('falls back gracefully when metric is not in the catalogue', () async {
      final input = File('${dir.path}/custom.json');
      await input.writeAsString(
        jsonEncode({
          'version': '1.0',
          'metrics': [
            {
              'file': 'lib/foo.dart',
              'scope': {'type': 'function', 'name': 'foo', 'line': 1},
              'values': {'custom-embedder-metric': 99},
              'violations': [
                {
                  'id': 'aaa1234567890abc',
                  'metric': 'custom-embedder-metric',
                  'level': 'warning',
                  'threshold': 1,
                },
              ],
            },
          ],
          'unused': <Object>[],
        }),
      );
      final output = '${dir.path}/out.yaml';
      final code = await buildCommandRunner().run([
        'explain',
        'aaa1234567890abc',
        '--input',
        input.path,
        '--output',
        output,
      ]);
      expect(code, 0);
      final body = await File(output).readAsString();
      expect(body, contains('explain: null'));
      expect(body, contains('not in built-in catalogue'));
    });
  });
}
