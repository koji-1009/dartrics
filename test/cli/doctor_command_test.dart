import 'dart:io';

import 'package:dartrics/src/cli/doctor_command.dart';
import 'package:dartrics/src/config/config.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('diagnose (pure)', () {
    test('clean config produces no issues', () {
      const config = Config(
        metricThresholds: {
          'cyclomatic-complexity': MetricThresholds(warning: 10, error: 20),
        },
      );
      expect(diagnose(config), isEmpty);
    });

    test('unknown metric id is flagged with did-you-mean', () {
      const config = Config(
        metricThresholds: {
          'cylomatic-complexity': MetricThresholds(warning: 10),
        },
      );
      final issues = diagnose(config);
      expect(issues, hasLength(1));
      expect(issues.single.message, contains('cylomatic-complexity'));
      expect(issues.single.hint, contains('cyclomatic-complexity'));
    });

    test('unknown metric id without close match has no hint', () {
      const config = Config(
        metricThresholds: {
          'totally-bogus-metric': MetricThresholds(warning: 1),
        },
      );
      final issues = diagnose(config);
      expect(issues, hasLength(1));
      expect(issues.single.hint, isNull);
    });

    test('down-polarity metric with error < warning is flagged', () {
      const config = Config(
        metricThresholds: {
          'cyclomatic-complexity': MetricThresholds(warning: 20, error: 10),
        },
      );
      final issues = diagnose(config);
      expect(issues, hasLength(1));
      expect(issues.single.message, contains('"down"'));
      expect(issues.single.message, contains('error=10'));
      expect(issues.single.message, contains('warning=20'));
    });

    test('down-polarity with error == warning is allowed', () {
      const config = Config(
        metricThresholds: {
          'cyclomatic-complexity': MetricThresholds(warning: 10, error: 10),
        },
      );
      expect(diagnose(config), isEmpty);
    });

    test('up-polarity metric with error > warning is flagged', () {
      // No built-in metric currently uses up polarity (MI was retired
      // in 0.1.0). The path stays live for custom embedder metrics —
      // exercise it directly via the public helper.
      final issue = checkThresholdOrdering(
        'custom-up-metric',
        const MetricThresholds(warning: 50, error: 80),
        'up',
      );
      expect(issue, isNotNull);
      expect(issue!.message, contains('"up"'));
    });

    test('up-polarity with error < warning is allowed', () {
      expect(
        checkThresholdOrdering(
          'custom-up-metric',
          const MetricThresholds(warning: 80, error: 50),
          'up',
        ),
        isNull,
      );
    });

    test('partial threshold (warning only) skips ordering check', () {
      const config = Config(
        metricThresholds: {
          'cyclomatic-complexity': MetricThresholds(warning: 10),
        },
      );
      expect(diagnose(config), isEmpty);
    });

    test('neutral-polarity metric skips ordering check', () {
      const config = Config(
        metricThresholds: {
          'halstead-volume': MetricThresholds(warning: 1000, error: 100),
        },
      );
      // halstead-volume is polarity=neutral; whatever ordering the user
      // wrote is their call to make.
      expect(diagnose(config), isEmpty);
    });

    test('unknown unused preset is flagged with did-you-mean', () {
      const config = Config(unused: UnusedConfig(presets: ['frezed']));
      final issues = diagnose(config);
      expect(issues, hasLength(1));
      expect(issues.single.message, contains('frezed'));
      expect(issues.single.hint, contains('freezed'));
    });

    test('multiple issues accumulate', () {
      const config = Config(
        metricThresholds: {
          'cyclomatic-complexity': MetricThresholds(warning: 20, error: 10),
          'cylomatic-complexity': MetricThresholds(warning: 1),
        },
        unused: UnusedConfig(presets: ['frezed', 'unknown']),
      );
      final issues = diagnose(config);
      expect(issues, hasLength(4));
    });
  });

  group('doctor CLI', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('doctor_cli_');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('exits 0 on a clean analysis_options.yaml', () async {
      final f = File('${dir.path}/analysis_options.yaml');
      await f.writeAsString('''
dartrics:
  metrics:
    cyclomatic-complexity:
      warning: 10
      error: 20
''');
      final code = await runQuietly(['doctor', '--config', f.path]);
      expect(code, 0);
    });

    test('exits 1 on warnings (typo metric id)', () async {
      final f = File('${dir.path}/analysis_options.yaml');
      await f.writeAsString('''
dartrics:
  metrics:
    cylomatic-complexity:
      warning: 10
''');
      final code = await runQuietly(['doctor', '--config', f.path]);
      expect(code, 1);
    });

    test('exits 78 (EX_CONFIG) on malformed YAML', () async {
      final f = File('${dir.path}/analysis_options.yaml');
      await f.writeAsString('dartrics:\n  metrics:\n    {broken\n');
      final code = await runQuietly(['doctor', '--config', f.path]);
      expect(code, 78);
    });

    test('exits 0 when config file is missing (defaults are clean)', () async {
      final code = await runQuietly([
        'doctor',
        '--config',
        '${dir.path}/missing.yaml',
      ]);
      expect(code, 0);
    });
  });
}
