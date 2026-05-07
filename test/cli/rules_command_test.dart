import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartrics/src/cli/rules_command.dart';
import 'package:dartrics/src/models/analysis_report.dart';
import 'package:dartrics/src/reporters/rules_reporter.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('collectRuleDescriptions yields one entry per built-in metric', () {
    final ids = collectRuleDescriptions().map((r) => r.id).toSet();
    expect(ids, containsAll(['cyclomatic-complexity', 'lcom4', 'instability']));
  });

  test('findRuleDescription returns null for unknown ids', () {
    expect(findRuleDescription('unknown-metric'), isNull);
    expect(findRuleDescription('cyclomatic-complexity'), isNotNull);
  });

  group('rules CLI', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('rules_cli_');
    });
    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('default ai reporter writes a yaml-ish bundle', () async {
      final out = '${dir.path}/rules.yaml';
      final code = await runQuietly(['rules', '--output', out]);
      expect(code, 0);
      final body = await File(out).readAsString();
      expect(body, contains('# dartrics rules v1'));
      expect(body, contains('cyclomatic-complexity'));
    });

    test('--reporter md emits a markdown catalogue', () async {
      final out = '${dir.path}/rules.md';
      final code = await runQuietly([
        'rules',
        '--reporter',
        'md',
        '--output',
        out,
      ]);
      expect(code, 0);
      final body = await File(out).readAsString();
      expect(body, contains('# dartrics rules'));
      expect(body, contains('## `cyclomatic-complexity`'));
    });

    test('--reporter json emits structured rules', () async {
      final out = '${dir.path}/rules.json';
      final code = await runQuietly([
        'rules',
        '--reporter',
        'json',
        '--output',
        out,
      ]);
      expect(code, 0);
      final decoded =
          jsonDecode(await File(out).readAsString()) as Map<String, Object?>;
      final list = (decoded['rules']! as List).cast<Map<String, Object?>>();
      expect(list, isNotEmpty);
      expect(list.first, containsPair('rationale', isNotEmpty));
    });

    test('--reporter console emits a one-rule-per-line summary', () async {
      final out = '${dir.path}/rules.txt';
      final code = await runQuietly([
        'rules',
        '--reporter',
        'console',
        '--output',
        out,
      ]);
      expect(code, 0);
      expect(
        await File(out).readAsString(),
        contains('cyclomatic-complexity [function]'),
      );
    });

    test('--output - prints rules to stdout', () async {
      final r = await runCaptured([
        'rules',
        '--reporter',
        'json',
        '--output',
        '-',
      ]);
      expect(r.exitCode, 0);
      expect(r.stdout, contains('cyclomatic-complexity'));
    });
  });

  test('RuleDescription.toJson omits absent threshold', () {
    final json = const RuleDescription(
      id: 'metric-x',
      scope: 'function',
      defaultEnabled: true,
      defaultThreshold: null,
      rationale: 'why',
      refactorHints: ['hint'],
    ).toJson();
    expect(json.containsKey('defaultThreshold'), isFalse);
  });

  test('buildExplanations dedupes ids, blanks, and unknowns', () async {
    // The "unknown-metric" branch writes to stderr (the function itself
    // does not throw); redirect into a discard sink so the message
    // does not leak into the test reporter's stream.
    final ctl = StreamController<List<int>>();
    unawaited(ctl.stream.drain<void>());
    final sink = IOSink(ctl.sink);
    final explanations = await withDartricsIO(
      () => buildExplanations([
        'cyclomatic-complexity',
        'cyclomatic-complexity', // duplicate
        ' ', // blank
        'unknown-metric', // unknown — written to stderr, dropped
      ]),
      stderrSink: sink,
    );
    await sink.close();
    await ctl.close();
    expect(explanations, hasLength(1));
    expect(explanations.single.metricId, 'cyclomatic-complexity');
  });

  test('analyze --explain injects an explanation block in JSON', () async {
    final dir = await Directory.systemTemp.createTemp('rules_inject_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/lib').create();
    await File('${dir.path}/lib/a.dart').writeAsString('void a() {}\n');
    // Snapshot off — we already exercised that path elsewhere.
    final out = '${dir.path}/run.json';
    final code = await runQuietly([
      'analyze',
      '${dir.path}/lib',
      '--reporter',
      'ai',
      '--output',
      out,
      '--explain',
      'cyclomatic-complexity',
      '--snapshot',
      'none',
      '--config',
      '${dir.path}/no.yaml',
    ]);
    expect(code, 0);
    final body = await File(out).readAsString();
    expect(body, contains('explain:'));
    expect(body, contains('cyclomatic-complexity'));
  });

  test('AnalysisReport carries explanations + analyzedFiles in JSON', () {
    final report = AnalysisReport(
      version: '1.0',
      metrics: const [],
      unused: const [],
      analyzedFiles: const [AnalyzedFile(path: 'a.dart', sha256: 'abc')],
      explanations: const [
        ExplainEntry(metricId: 'm', rationale: 'r', refactorHints: ['h']),
      ],
    );
    final json = report.toJson();
    expect(json['analyzedFiles'], isNotNull);
    final list = json['analyzedFiles']! as List;
    expect(list.first, containsPair('path', 'a.dart'));
  });

  test('AnalyzedFile.fromJson round-trips', () {
    const original = AnalyzedFile(path: 'a.dart', sha256: 'abc');
    final round = AnalyzedFile.fromJson(original.toJson());
    expect(round.path, 'a.dart');
    expect(round.sha256, 'abc');
  });
}
