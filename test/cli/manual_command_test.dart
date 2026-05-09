import 'dart:convert';
import 'dart:io';

import 'package:dartrics/src/cli/manual_text.dart';
import 'package:dartrics/src/cli/runner.dart';
import 'package:dartrics/src/metrics/metric_catalogue.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('manual subcommand', () {
    test('manualText is byte-identical to doc/manual.md', () {
      final docBytes = _findManualMd().readAsBytesSync();
      final stringBytes = utf8.encode(manualText);
      expect(
        stringBytes,
        equals(docBytes),
        reason:
            'lib/src/cli/manual_text.dart and doc/manual.md drifted. '
            'Re-mirror the manual into the const string (or vice versa) '
            'so `dartrics manual` keeps printing the documented manual.',
      );
    });

    test('writes manual to --output path', () async {
      final dir = await Directory.systemTemp.createTemp('manual_cli_');
      try {
        final out = '${dir.path}/MANUAL.md';
        final code = await runQuietly(['manual', '--output', out]);
        expect(code, 0);
        final body = await File(out).readAsString();
        expect(body, equals(manualText));
        expect(body, contains('# dartrics manual'));
        expect(body, contains('The lens battery'));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('--output - prints manual to stdout', () async {
      final r = await runCaptured(['manual', '--output', '-']);
      expect(r.exitCode, 0);
      expect(r.stdout, equals(manualText));
    });

    test('appears in the top-level help', () {
      final usage = buildCommandRunner().usage;
      expect(usage, contains('manual'));
      expect(usage, contains("operator's manual"));
    });

    test('documents every built-in lens', () {
      final ids = collectRuleDescriptions().map((r) => r.id).toList();
      for (final id in ids) {
        expect(
          manualText,
          contains('`$id`'),
          reason:
              '`$id` is in collectRuleDescriptions() but no `\\`$id\\`` '
              'token appears in doc/manual.md. Add a row for it under '
              '"## The lens battery" or remove the metric.',
        );
      }
    });

    test('does not document lenses that no longer exist', () {
      final knownIds = collectRuleDescriptions().map((r) => r.id).toSet();
      // Walk only the `## The lens battery` section so back-ticked
      // tokens in other sections (`if`, `package:`, `MethodInvocation`,
      // …) are not mistaken for metric ids.
      final region = _lensBatterySection(manualText);
      // Each lens row starts with `| \`<id>\``; pull the leading id
      // from every such row, ignoring the `(off)` / `(Ce)` suffixes.
      final pattern = RegExp(r'^\|\s*`([a-z][a-z0-9-]+)`', multiLine: true);
      final mentioned = pattern
          .allMatches(region)
          .map((m) => m.group(1)!)
          .toSet();
      final stale = mentioned.difference(knownIds);
      expect(
        stale,
        isEmpty,
        reason:
            'doc/manual.md mentions $stale under `## The lens battery` '
            'but $stale is not registered with collectRuleDescriptions(). '
            'Remove the stale row or re-register the metric.',
      );
    });
  });
}

/// Slices `manualText` to the `## The lens battery` body — from that
/// heading up to (but not including) the next `## ` heading. Returns an
/// empty string if the section is missing, which fails the caller's
/// assertion with a clear "manual layout changed" reason.
String _lensBatterySection(String text) {
  final start = text.indexOf('## The lens battery');
  if (start < 0) return '';
  final after = text.indexOf('\n## ', start + 1);
  return after < 0 ? text.substring(start) : text.substring(start, after);
}

/// Walk the cwd ancestors until `doc/manual.md` is found. Tests can run
/// from the repo root or a workspace package; either should work.
File _findManualMd() {
  Directory dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final candidate = File('${dir.path}/doc/manual.md');
    if (candidate.existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('doc/manual.md not found from ${Directory.current.path}');
}
