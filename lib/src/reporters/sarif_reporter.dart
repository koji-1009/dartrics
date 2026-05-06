import 'dart:convert';
import 'dart:io';

import '../models/analysis_report.dart';
import 'reporter.dart';

/// SARIF 2.1.0 reporter — produces a static-analysis result file consumable
/// by GitHub Code Scanning, GitLab, and any other tool that ingests SARIF.
/// Schema reference:
/// https://docs.oasis-open.org/sarif/sarif/v2.1.0/os/sarif-v2.1.0-os.html.
class SarifReporter implements Reporter {
  @override
  void report(AnalysisReport report, IOSink sink) {
    final results = <Map<String, Object?>>[];
    for (final m in report.metrics) {
      for (final v in m.violations) {
        results.add({
          'ruleId': v.metricId,
          'level': _level(v.severity),
          if (v.id.isNotEmpty) 'partialFingerprints': {'dartrics/v1': v.id},
          'message': {
            'text':
                '${v.metricId} = ${m.values[v.metricId]} '
                'exceeds the ${v.severity.name} threshold of ${v.threshold} '
                'in ${m.scope.name}.',
          },
          'locations': [
            {
              'physicalLocation': {
                'artifactLocation': {'uri': m.file},
                'region': {
                  'startLine': m.scope.location.line,
                  'startColumn': m.scope.location.column,
                },
              },
            },
          ],
        });
      }
    }
    for (final u in report.unused) {
      results.add({
        'ruleId': 'unused-declaration',
        'level': 'warning',
        'message': {
          'text':
              'Public ${u.kind.name} `${u.name}` is never reached '
              'from any entry point.',
        },
        'locations': [
          {
            'physicalLocation': {
              'artifactLocation': {'uri': u.location.path},
              'region': {
                'startLine': u.location.line,
                'startColumn': u.location.column,
              },
            },
          },
        ],
      });
    }

    final document = {
      r'$schema':
          'https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json',
      'version': '2.1.0',
      'runs': [
        {
          'tool': {
            'driver': {
              'name': 'dartrics',
              'informationUri': 'https://pub.dev/packages/dartrics',
              'rules': _rulesFor(report),
            },
          },
          'results': results,
        },
      ],
    };
    sink.writeln(const JsonEncoder.withIndent('  ').convert(document));
  }

  String _level(Severity s) {
    switch (s) {
      case Severity.error:
        return 'error';
      case Severity.warning:
        return 'warning';
      case Severity.info:
        return 'note';
    }
  }

  List<Map<String, Object?>> _rulesFor(AnalysisReport report) {
    final ids = <String>{};
    for (final m in report.metrics) {
      for (final v in m.violations) {
        ids.add(v.metricId);
      }
    }
    if (report.unused.isNotEmpty) ids.add('unused-declaration');
    return [
      for (final id in ids)
        {
          'id': id,
          'shortDescription': {'text': id},
        },
    ];
  }
}
