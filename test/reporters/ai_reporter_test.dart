import 'dart:io';

import 'package:dartrics/src/models/analysis_report.dart';
import 'package:dartrics/src/reporters/ai_reporter.dart';
import 'package:test/test.dart';

import 'sample_report.dart';

void main() {
  test('emits violations and unused with snippet placeholder', () async {
    final tmp = Directory.systemTemp.createTempSync();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final temp = File('${tmp.path}/ai.yaml');
    final sink = temp.openWrite();
    AiReporter(
      sourceLoader: (path) => {
        path: List.generate(100, (i) => 'line${i + 1}').join('\n'),
      },
    ).report(buildSampleReport(), sink);
    await sink.close();

    final body = await temp.readAsString();
    expect(body, contains('dartrics ai-report v1'));
    expect(body, contains('violations:'));
    expect(body, contains('cyclomatic-complexity'));
    expect(body, contains('unused:'));
    expect(body, contains('_legacyFormatter'));
  });

  test('renders an explain block when explanations are attached', () async {
    final tmp = Directory.systemTemp.createTempSync();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final temp = File('${tmp.path}/ai.yaml');
    final sink = temp.openWrite();
    final report = buildSampleReport(
      explanations: const [
        ExplainEntry(
          metricId: 'cyclomatic-complexity',
          rationale: 'Multi\nline rationale: with colon and # hash.',
          refactorHints: ['Plain hint.', 'Has: colon hint.'],
        ),
      ],
    );
    AiReporter(
      sourceLoader: (path) => {
        path: List.generate(100, (i) => 'line${i + 1}').join('\n'),
      },
    ).report(report, sink);
    await sink.close();

    final body = await temp.readAsString();
    expect(body, contains('explain:'));
    expect(body, contains('Multi'));
    expect(body, contains('"Has: colon hint."'));
  });
}
