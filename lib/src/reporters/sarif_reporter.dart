import 'dart:convert';
import 'dart:io';

import '../metrics/metric_catalogue.dart';
import '../models/analysis_report.dart';
import '../models/unused_declaration.dart';
import 'reporter.dart';
import 'rules_reporter.dart';

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
              'Public ${unusedKindJsonName(u.kind)} `${u.name}` is never reached '
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

  /// Builds `tool.driver.rules` so GitHub Code Scanning / GitLab show
  /// the metric's rationale + refactor hints inline next to the result,
  /// rather than just an opaque rule id. Only the rules that actually
  /// produced a result in [report] are emitted, matching the SARIF 2.1.0
  /// guidance that `rules` should be the rules consulted, not every
  /// rule the tool ships.
  List<Map<String, Object?>> _rulesFor(AnalysisReport report) {
    final firedMetrics = <String>{};
    for (final m in report.metrics) {
      for (final v in m.violations) {
        firedMetrics.add(v.metricId);
      }
    }

    final rules = <Map<String, Object?>>[];
    for (final id in firedMetrics) {
      final desc = findRuleDescription(id);
      if (desc == null) {
        // Metric without a registered description (custom embedder).
        // Surface the bare id so consumers still resolve a rule entry,
        // but don't fabricate metadata we don't have.
        rules.add({
          'id': id,
          'shortDescription': {'text': id},
        });
        continue;
      }
      rules.add(_metricRule(desc));
    }

    if (report.unused.isNotEmpty) rules.add(_unusedRule());
    return rules;
  }

  /// SARIF rule object for a built-in metric. The `name` is a
  /// PascalCased form of the kebab-case id (GitHub Code Scanning's
  /// preference). `helpUri` points at the package's `Provided metrics`
  /// section on pub.dev — that anchor exists and lists every shipped
  /// metric with its citation. (Per-metric anchors aren't generated
  /// because metrics live in tables rather than under their own
  /// headings; the section anchor is the closest stable target.)
  Map<String, Object?> _metricRule(RuleDescription desc) {
    return {
      'id': desc.id,
      'name': _toPascalCase(desc.id),
      'shortDescription': {'text': _firstSentence(desc.rationale)},
      'fullDescription': {'text': desc.rationale},
      'helpUri': 'https://pub.dev/packages/dartrics#provided-metrics',
      'help': {'text': _helpText(desc), 'markdown': _helpMarkdown(desc)},
      'properties': {
        'tags': ['dartrics', desc.scope],
        if (desc.defaultThreshold != null)
          'defaultThreshold': desc.defaultThreshold,
      },
    };
  }

  /// SARIF rule object for the public-API unused-declaration check.
  /// Distinct from a metric — its description is hand-authored.
  Map<String, Object?> _unusedRule() {
    const text =
        'Public-API reachability check (Periphery-style BFS over a '
        'name-based reference graph). Reports public declarations that no '
        "entry point reaches. Roots are `main`, `@pragma('vm:entry-point')`, "
        'and `lib/` exports outside `lib/src/` (when `excludeExported` is '
        'on). Private (underscore-prefixed) names are intentionally '
        "skipped — `dart analyze`'s `dead_code` lint already covers them.";
    return {
      'id': 'unused-declaration',
      'name': 'UnusedDeclaration',
      'shortDescription': {
        'text': 'Public declaration is never reached from any entry point.',
      },
      'fullDescription': {'text': text},
      'helpUri':
          'https://pub.dev/packages/dartrics#public-api-unused-code-detection',
      'properties': {
        'tags': ['dartrics', 'unused'],
      },
    };
  }

  String _firstSentence(String paragraph) {
    final period = paragraph.indexOf('. ');
    if (period < 0) return paragraph;
    return paragraph.substring(0, period + 1);
  }

  String _toPascalCase(String kebab) {
    return kebab
        .split('-')
        .map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1))
        .join();
  }

  String _helpText(RuleDescription desc) {
    final hints = desc.refactorHints.map((String h) => '- $h').join('\n');
    final base = '${desc.rationale}\n\nRefactor hints:\n$hints';
    if (desc.references.isEmpty) return base;
    final refs = desc.references.map((String r) => '- $r').join('\n');
    return '$base\n\nReferences:\n$refs';
  }

  String _helpMarkdown(RuleDescription desc) {
    final hints = desc.refactorHints.map((String h) => '- $h').join('\n');
    final base = '${desc.rationale}\n\n**Refactor hints:**\n\n$hints';
    if (desc.references.isEmpty) return base;
    final refs = desc.references.map((String r) => '- $r').join('\n');
    return '$base\n\n**References:**\n\n$refs';
  }
}
