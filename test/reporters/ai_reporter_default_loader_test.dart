import 'dart:io';

import 'package:dartrics/src/models/analysis_report.dart';
import 'package:dartrics/src/models/source_location.dart';
import 'package:dartrics/src/models/unused_declaration.dart';
import 'package:dartrics/src/reporters/ai_reporter.dart';
import 'package:test/test.dart';

void main() {
  test('default source loader reads file from disk and falls back on missing files', () async {
    final dir = await Directory.systemTemp.createTemp('ai_default_loader_');
    addTearDown(() => dir.delete(recursive: true));

    final realFile = File('${dir.path}/real.dart');
    await realFile.writeAsString(
      List.generate(20, (i) => 'line${i + 1}').join('\n'),
    );

    final report = AnalysisReport(
      version: '1.0',
      metrics: [
        MetricRecord(
          file: realFile.path,
          scope: ScopeRef(
            kind: ScopeKind.function,
            name: 'f',
            location: SourceLocation(path: realFile.path, line: 5, column: 1),
          ),
          values: const {'cyclomatic-complexity': 12},
          violations: const [
            MetricViolation(
              metricId: 'cyclomatic-complexity',
              severity: Severity.warning,
              threshold: 10,
            ),
          ],
        ),
      ],
      unused: [
        UnusedDeclaration(
          kind: UnusedKind.function,
          name: 'orphan',
          location: SourceLocation(
            path: '${dir.path}/missing.dart',
            line: 2,
            column: 1,
          ),
        ),
      ],
    )..attachAnalyzedFileCount(1);

    final out = File('${dir.path}/out.yaml');
    final sink = out.openWrite();
    AiReporter().report(report, sink);
    await sink.close();

    final body = await out.readAsString();
    expect(body, contains('cyclomatic-complexity'));
    // Snippet should contain lines from the real file.
    expect(body, contains('line5'));
    // Missing file's snippet falls through the FileSystemException path —
    // the report still completes and lists the unused entry.
    expect(body, contains('orphan'));
  });
}
