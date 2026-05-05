import 'dart:convert';
import 'dart:io';

import 'package:dartrics/src/cli/runner.dart';
import 'package:test/test.dart';

void main() {
  group('Phase 0 smoke', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dartrics_phase0_');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('analyze empty package produces an empty json report', () async {
      final outputFile = File('${tempDir.path}/report.json');
      final runner = buildCommandRunner();
      final code = await runner.run([
        'analyze',
        tempDir.path,
        '--reporter',
        'json',
        '--output',
        outputFile.path,
        '--config',
        '${tempDir.path}/no-such-config.yaml',
      ]);
      expect(code, 0);

      final body = jsonDecode(outputFile.readAsStringSync());
      expect(body['version'], '1.0');
      expect(body['metrics'], isEmpty);
      expect(body['unused'], isEmpty);
    });

    test('unused subcommand exits 0 (Phase 0 stub)', () async {
      final runner = buildCommandRunner();
      final code = await runner.run([
        'unused',
        tempDir.path,
        '--config',
        '${tempDir.path}/no-such-config.yaml',
      ]);
      expect(code, 0);
    });
  });
}
