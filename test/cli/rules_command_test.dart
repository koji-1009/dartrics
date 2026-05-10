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

  group('references field', () {
    test('every cited metric carries at least one structured reference', () {
      // Pin the contract that metrics whose rationale names a primary
      // source also expose that source through the structured
      // `references` getter; the AI report and `dartrics rules` consume
      // the structured list rather than parsing the prose.
      const citedIds = {
        'cyclomatic-complexity',
        'cognitive-complexity',
        'maximum-nesting-level',
        'number-of-parameters',
        'boolean-trap',
        'method-length',
        'halstead-volume',
        'source-lines-of-code',
        'lcom4',
        'weighted-methods-per-class',
        'coupling-between-objects',
        'response-for-class',
        'efferent-coupling',
        'afferent-coupling',
        'instability',
        'abstractness',
        'distance-from-main-sequence',
      };
      final byId = {for (final r in collectRuleDescriptions()) r.id: r};
      for (final id in citedIds) {
        final desc = byId[id];
        expect(desc, isNotNull, reason: 'missing rule description for $id');
        expect(
          desc!.references,
          isNotEmpty,
          reason:
              '$id mentions a primary source in its rationale but does not '
              'expose it through `references`. Add the citation to the '
              'metric calculator.',
        );
      }
    });

    test('RuleDescription.toJson omits absent references', () {
      final json = const RuleDescription(
        id: 'metric-x',
        scope: 'function',
        defaultEnabled: true,
        defaultThreshold: null,
        rationale: 'why',
        refactorHints: ['hint'],
      ).toJson();
      expect(json.containsKey('references'), isFalse);
    });

    test('RuleDescription.toJson surfaces non-empty references', () {
      final json = const RuleDescription(
        id: 'metric-x',
        scope: 'function',
        defaultEnabled: true,
        defaultThreshold: null,
        rationale: 'why',
        refactorHints: ['hint'],
        references: ['Author (Year). Title.'],
      ).toJson();
      expect(json, containsPair('references', ['Author (Year). Title.']));
    });

    test(
      'rules CLI surfaces references in ai / md / console / json reporters',
      () async {
        final dir = await Directory.systemTemp.createTemp('rules_refs_');
        addTearDown(() => dir.delete(recursive: true));

        final ai = '${dir.path}/r.yaml';
        expect(await runQuietly(['rules', '--output', ai]), 0);
        final aiBody = await File(ai).readAsString();
        expect(aiBody, contains('references:'));
        expect(aiBody, contains('McCabe'));

        final md = '${dir.path}/r.md';
        expect(
          await runQuietly(['rules', '--reporter', 'md', '--output', md]),
          0,
        );
        final mdBody = await File(md).readAsString();
        expect(mdBody, contains('**References:**'));

        final console = '${dir.path}/r.txt';
        expect(
          await runQuietly([
            'rules',
            '--reporter',
            'console',
            '--output',
            console,
          ]),
          0,
        );
        expect(await File(console).readAsString(), contains('  ref: McCabe'));

        final json = '${dir.path}/r.json';
        expect(
          await runQuietly(['rules', '--reporter', 'json', '--output', json]),
          0,
        );
        final decoded =
            jsonDecode(await File(json).readAsString()) as Map<String, Object?>;
        final list = (decoded['rules']! as List).cast<Map<String, Object?>>();
        final cc = list.firstWhere((r) => r['id'] == 'cyclomatic-complexity');
        expect(cc['references'], isA<List<Object?>>());
        expect((cc['references']! as List).first, contains('McCabe'));
      },
    );
  });
}
