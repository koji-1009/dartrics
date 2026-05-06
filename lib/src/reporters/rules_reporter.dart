import 'dart:convert';
import 'dart:io';

import 'package:dapper/dapper.dart';

/// Lightweight description of a single metric rule, used by the
/// `dartrics rules` subcommand and by the `--explain` injection in the
/// analyze/unused reporters.
class RuleDescription {
  const RuleDescription({
    required this.id,
    required this.scope,
    required this.defaultEnabled,
    required this.defaultThreshold,
    required this.rationale,
    required this.refactorHints,
  });

  /// Stable metric id (e.g. `cyclomatic-complexity`).
  final String id;

  /// Scope of the metric — `function`, `class`, or `library`.
  final String scope;

  /// Whether the metric runs out of the box.
  final bool defaultEnabled;

  /// Built-in warning threshold, or `null` if the metric ships without one.
  final num? defaultThreshold;

  /// Paragraph from the metric's `rationale` getter.
  final String rationale;

  /// List from the metric's `refactorHints` getter.
  final List<String> refactorHints;

  Map<String, Object?> toJson() => {
    'id': id,
    'scope': scope,
    'defaultEnabled': defaultEnabled,
    if (defaultThreshold != null) 'defaultThreshold': defaultThreshold,
    'rationale': rationale,
    'refactorHints': refactorHints,
  };
}

/// Renders [RuleDescription]s in one of the supported formats.
class RulesReporter {
  const RulesReporter();

  void report(List<RuleDescription> rules, IOSink sink, String format) {
    switch (format) {
      case 'json':
        const encoder = JsonEncoder.withIndent('  ');
        sink.writeln(
          encoder.convert({'rules': rules.map((r) => r.toJson()).toList()}),
        );
        return;
      case 'md':
        sink.write(formatMarkdown(_renderMarkdown(rules)));
        return;
      case 'console':
        sink.write(_renderConsole(rules));
        return;
      case 'ai':
      default:
        sink.write(formatYaml(_renderAi(rules)));
        return;
    }
  }

  String _renderAi(List<RuleDescription> rules) {
    final buf = StringBuffer()..writeln('# dartrics rules v1');
    buf.writeln('rules:');
    for (final r in rules) {
      buf
        ..writeln('  - id: ${r.id}')
        ..writeln('    scope: ${r.scope}')
        ..writeln('    defaultEnabled: ${r.defaultEnabled}');
      if (r.defaultThreshold != null) {
        buf.writeln('    defaultThreshold: ${r.defaultThreshold}');
      }
      buf
        ..writeln('    rationale: |')
        ..writeln('      ${r.rationale.replaceAll('\n', '\n      ')}')
        ..writeln('    refactorHints:');
      for (final hint in r.refactorHints) {
        buf.writeln('      - ${_escapeYamlInline(hint)}');
      }
    }
    return buf.toString();
  }

  String _renderMarkdown(List<RuleDescription> rules) {
    final buf = StringBuffer()
      ..writeln('# dartrics rules')
      ..writeln();
    for (final r in rules) {
      buf
        ..writeln('## `${r.id}` *(${r.scope})*')
        ..writeln()
        ..writeln(
          '- default: ${r.defaultEnabled ? 'on' : 'off'}'
          '${r.defaultThreshold == null ? '' : ' · warning ≥ ${r.defaultThreshold}'}',
        )
        ..writeln()
        ..writeln(r.rationale)
        ..writeln()
        ..writeln('**Refactor hints:**')
        ..writeln();
      for (final hint in r.refactorHints) {
        buf.writeln('- $hint');
      }
      buf.writeln();
    }
    return buf.toString();
  }

  String _renderConsole(List<RuleDescription> rules) {
    final buf = StringBuffer();
    for (final r in rules) {
      buf.writeln(
        '${r.id} [${r.scope}] '
        'default=${r.defaultEnabled ? 'on' : 'off'}'
        '${r.defaultThreshold == null ? '' : ' threshold=${r.defaultThreshold}'}',
      );
      buf.writeln('  ${r.rationale}');
      for (final hint in r.refactorHints) {
        buf.writeln('  - $hint');
      }
    }
    return buf.toString();
  }

  String _escapeYamlInline(String value) {
    if (value.contains(':') || value.contains('#')) {
      return '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
    }
    return value;
  }
}
