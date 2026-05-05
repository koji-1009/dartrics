import 'dart:io';

import 'package:dartrics/src/reporters/ai_reporter.dart';
import 'package:test/test.dart';

import '_test_report.dart';

void main() {
  test('emits violations and unused with snippet placeholder', () async {
    final tmp = Directory.systemTemp.createTempSync();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final temp = File('${tmp.path}/ai.yaml');
    final sink = temp.openWrite();
    AiReporter(
      sourceLoader: (path) => {path: 'line1\nline2\nline3\nline4\nline5\n'},
    ).report(buildSampleReport(), sink);
    await sink.close();

    final body = await temp.readAsString();
    expect(body, contains('dartrics ai-report v1'));
    expect(body, contains('violations:'));
    expect(body, contains('cyclomatic-complexity'));
    expect(body, contains('unused:'));
    expect(body, contains('_legacyFormatter'));
  });
}
