import 'dart:convert';
import 'dart:io';

import 'package:dartrics/src/cli/manual_text.dart';
import 'package:dartrics/src/cli/runner.dart';
import 'package:test/test.dart';

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
        final code = await buildCommandRunner().run([
          'manual',
          '--output',
          out,
        ]);
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
      final code = await buildCommandRunner().run(['manual', '--output', '-']);
      expect(code, 0);
    });

    test('appears in the top-level help', () {
      final usage = buildCommandRunner().usage;
      expect(usage, contains('manual'));
      expect(usage, contains("operator's manual"));
    });
  });
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
