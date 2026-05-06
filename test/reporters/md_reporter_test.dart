import 'dart:io';

import 'package:dartrics/src/models/analysis_report.dart';
import 'package:dartrics/src/reporters/md_reporter.dart';
import 'package:test/test.dart';

import 'sample_report.dart';

void main() {
  test('emits sections, summary table, violations, unused', () async {
    final temp = await File.fromUri(
      Uri.file('${Directory.systemTemp.createTempSync().path}/r.md'),
    ).create();
    final sink = temp.openWrite();
    MdReporter().report(buildSampleReport(), sink);
    await sink.close();

    final body = await temp.readAsString();
    expect(body, contains('# dartrics report'));
    expect(body, contains('## Summary'));
    expect(body, contains('## Violations'));
    expect(body, contains('Foo.bar'));
    expect(body, contains('cyclomatic-complexity'));
    expect(body, contains('## Unused Declarations'));
    expect(body, contains('_legacyFormatter'));
  });

  test(
    'renders an Explanations section when explanations are attached',
    () async {
      final temp = await File.fromUri(
        Uri.file('${Directory.systemTemp.createTempSync().path}/r.md'),
      ).create();
      final sink = temp.openWrite();
      MdReporter().report(
        buildSampleReport(
          explanations: const [
            ExplainEntry(
              metricId: 'cyclomatic-complexity',
              rationale: 'Why CC matters.',
              refactorHints: ['Extract helpers.'],
            ),
          ],
        ),
        sink,
      );
      await sink.close();
      final body = await temp.readAsString();
      expect(body, contains('## Explanations'));
      expect(body, contains('Why CC matters.'));
      expect(body, contains('Extract helpers.'));
    },
  );
}
