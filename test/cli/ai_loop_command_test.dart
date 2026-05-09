import 'dart:convert';
import 'dart:io';

import 'package:dartrics/src/cli/ai_loop_text.dart';
import 'package:dartrics/src/cli/runner.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('ai-loop subcommand', () {
    test('aiLoopText is byte-identical to doc/ai-loop.md', () {
      final docBytes = _findAiLoopMd().readAsBytesSync();
      final stringBytes = utf8.encode(aiLoopText);
      expect(
        stringBytes,
        equals(docBytes),
        reason:
            'lib/src/cli/ai_loop_text.dart and doc/ai-loop.md drifted. '
            'Re-mirror the walkthrough into the const string (or vice '
            'versa) so `dartrics ai-loop` keeps printing the documented '
            'walkthrough.',
      );
    });

    test('writes walkthrough to --output path', () async {
      final dir = await Directory.systemTemp.createTemp('ai_loop_cli_');
      try {
        final out = '${dir.path}/AI_LOOP.md';
        final code = await runQuietly(['ai-loop', '--output', out]);
        expect(code, 0);
        final body = await File(out).readAsString();
        expect(body, equals(aiLoopText));
        expect(body, contains('# AI loop walkthrough'));
        expect(body, contains('1. Setup'));
        expect(body, contains('2. Propose'));
        expect(body, contains('3. Apply'));
        expect(body, contains('4. Verify'));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('--output - prints walkthrough to stdout', () async {
      final r = await runCaptured(['ai-loop', '--output', '-']);
      expect(r.exitCode, 0);
      expect(r.stdout, equals(aiLoopText));
    });

    test('appears in the top-level help', () {
      final usage = buildCommandRunner().usage;
      expect(usage, contains('ai-loop'));
      expect(usage, contains('AI-loop walkthrough'));
    });
  });
}

/// Walk the cwd ancestors until `doc/ai-loop.md` is found. Tests can run
/// from the repo root or a workspace package; either should work.
File _findAiLoopMd() {
  Directory dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final candidate = File('${dir.path}/doc/ai-loop.md');
    if (candidate.existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('doc/ai-loop.md not found from ${Directory.current.path}');
}
