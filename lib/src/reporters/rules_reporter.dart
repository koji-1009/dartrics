import 'dart:convert';
import 'dart:io';

import 'package:dapper/dapper.dart';

import 'yaml_scalar.dart';

/// Lightweight description of a single metric rule, used by the
/// `dartrics rules` subcommand and by the auto-explain block injected
/// into the AI / md / SARIF reporters.
class RuleDescription {
  const RuleDescription({
    required this.id,
    required this.scope,
    required this.defaultEnabled,
    required this.defaultThreshold,
    required this.rationale,
    required this.refactorHints,
    this.references = const [],
    this.polarity = 'down',
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

  /// Citations the metric is anchored to (papers, books, specs).
  /// Mirrors the metric calculator's `references` getter; empty for
  /// metrics that don't trace to a published source. Surfaced by every
  /// reporter so an AI consumer can verify a metric against its
  /// primary source rather than paraphrasing from training data.
  final List<String> references;

  /// Direction in which the metric value moves when the code gets
  /// healthier. `'down'`, `'up'`, or `'neutral'` — mirrors
  /// `MetricPolarity` as a string so the JSON / AI / SARIF surfaces stay
  /// stable across changes to the enum. Default `'down'` matches
  /// `MetricPolarity.down`, the engine's own default.
  final String polarity;

  Map<String, Object?> toJson() => {
    'id': id,
    'scope': scope,
    'defaultEnabled': defaultEnabled,
    if (defaultThreshold != null) 'defaultThreshold': defaultThreshold,
    'polarity': polarity,
    'rationale': rationale,
    'refactorHints': refactorHints,
    if (references.isNotEmpty) 'references': references,
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
      case 'md':
        sink.write(formatMarkdown(_renderMarkdown(rules)));
      case 'console':
        sink.write(_renderConsole(rules));
      case 'ai' || _:
        sink.write(formatYaml(_renderAi(rules)));
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
        buf.writeln('      - ${yamlInlineScalar(hint)}');
      }
      if (r.references.isNotEmpty) {
        buf.writeln('    references:');
        for (final ref in r.references) {
          buf.writeln('      - ${yamlInlineScalar(ref)}');
        }
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
      if (r.references.isNotEmpty) {
        buf
          ..writeln()
          ..writeln('**References:**')
          ..writeln();
        for (final ref in r.references) {
          buf.writeln('- $ref');
        }
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
      for (final ref in r.references) {
        buf.writeln('  ref: $ref');
      }
    }
    return buf.toString();
  }
}
