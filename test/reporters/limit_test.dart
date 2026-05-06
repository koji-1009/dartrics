import 'dart:io';

import 'package:dartrics/src/models/analysis_report.dart';
import 'package:dartrics/src/models/source_location.dart';
import 'package:dartrics/src/models/unused_declaration.dart';
import 'package:dartrics/src/reporters/ai_reporter.dart';
import 'package:dartrics/src/reporters/md_reporter.dart';
import 'package:dartrics/src/reporters/reporters.dart';
import 'package:test/test.dart';

/// Builds a synthetic report with [n] warning-level violations spread
/// across distinct files.
AnalysisReport _buildReport({required int n}) {
  return AnalysisReport(
    version: '1.0',
    metrics: [
      for (var i = 0; i < n; i++)
        MetricRecord(
          file: '/proj/a$i.dart',
          scope: ScopeRef(
            kind: ScopeKind.function,
            name: 'fn$i',
            location: SourceLocation(
              path: '/proj/a$i.dart',
              line: 1,
              column: 1,
            ),
          ),
          values: const {'cyclomatic-complexity': 11},
          violations: const [
            MetricViolation(
              id: '0123456789abcdef',
              metricId: 'cyclomatic-complexity',
              severity: Severity.warning,
              threshold: 10,
            ),
          ],
        ),
    ],
    unused: [
      // (Placeholder — we don't need rich unused fixtures here.)
    ],
  );
}

void main() {
  group('AI reporter --limit', () {
    test('keeps every entry when limit is null', () async {
      final dir = await Directory.systemTemp.createTemp('ai_lim_');
      addTearDown(() => dir.delete(recursive: true));
      final out = File('${dir.path}/r.yaml');
      final sink = out.openWrite();
      AiReporter(
        sourceLoader: (path) => {path: 'line\n' * 10},
      ).report(_buildReport(n: 5), sink);
      await sink.close();
      final body = await out.readAsString();
      // 5 entries → 5 `- file:` bullets.
      expect(RegExp(r'^  - file:', multiLine: true).allMatches(body).length, 5);
      expect(body, isNot(contains('truncated:')));
    });

    test('truncates at the cap and emits the truncated block', () async {
      final dir = await Directory.systemTemp.createTemp('ai_lim_');
      addTearDown(() => dir.delete(recursive: true));
      final out = File('${dir.path}/r.yaml');
      final sink = out.openWrite();
      AiReporter(
        limit: 2,
        sourceLoader: (path) => {path: 'line\n' * 10},
      ).report(_buildReport(n: 5), sink);
      await sink.close();
      final body = await out.readAsString();
      expect(RegExp(r'^  - file:', multiLine: true).allMatches(body).length, 2);
      expect(body, contains('truncated:'));
      expect(body, contains('violations: 3'));
    });

    test('truncates the unused list independently of violations', () async {
      final dir = await Directory.systemTemp.createTemp('ai_lim_');
      addTearDown(() => dir.delete(recursive: true));
      final out = File('${dir.path}/r.yaml');
      final sink = out.openWrite();
      final report = AnalysisReport(
        version: '1.0',
        metrics: const [],
        unused: [
          for (var i = 0; i < 4; i++)
            UnusedDeclaration(
              kind: UnusedKind.function,
              name: 'unused_$i',
              location: SourceLocation(
                path: '/proj/u$i.dart',
                line: 1,
                column: 1,
              ),
            ),
        ],
      );
      AiReporter(
        limit: 2,
        sourceLoader: (path) => {path: 'line\n' * 10},
      ).report(report, sink);
      await sink.close();
      final body = await out.readAsString();
      expect(body, contains('unused:'));
      expect(body, contains('unused_0'));
      expect(body, contains('unused_1'));
      expect(body, isNot(contains('unused_3')));
      expect(body, contains('truncated:'));
      expect(body, contains('unused: 2'));
    });
  });

  group('Md reporter --limit', () {
    test('truncates bullets and prints "+ N more"', () async {
      final dir = await Directory.systemTemp.createTemp('md_lim_');
      addTearDown(() => dir.delete(recursive: true));
      final out = File('${dir.path}/r.md');
      final sink = out.openWrite();
      MdReporter(limit: 2).report(_buildReport(n: 5), sink);
      await sink.close();
      final body = await out.readAsString();
      // Two bullets land — the rest are summarised. `dapper.formatMarkdown`
      // normalises `-` to `*` so the regex matches the canonical form.
      expect(
        RegExp(
          r'^[*-] cyclomatic-complexity:',
          multiLine: true,
        ).allMatches(body).length,
        2,
      );
      expect(body, contains('+ 3 more'));
    });
  });

  test(
    'pickReporter wires the limit into ai and md, ignores it for json',
    () async {
      final dir = await Directory.systemTemp.createTemp('pick_lim_');
      addTearDown(() => dir.delete(recursive: true));
      final report = _buildReport(n: 3);
      for (final name in ['ai', 'md']) {
        final reporter = pickReporter(name, limit: 1);
        final sink = File('${dir.path}/$name.out').openWrite();
        reporter.report(report, sink);
        await sink.close();
        expect(File('${dir.path}/$name.out').readAsStringSync(), isNotEmpty);
      }
      // JSON keeps the full set even when limit is set.
      final json = pickReporter('json', limit: 1);
      final jsonSink = File('${dir.path}/r.json').openWrite();
      json.report(report, jsonSink);
      await jsonSink.close();
      final jsonBody = File('${dir.path}/r.json').readAsStringSync();
      expect(jsonBody, contains('a0.dart'));
      expect(jsonBody, contains('a2.dart'));
    },
  );
}
