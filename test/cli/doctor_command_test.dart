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

    test('misplaced analyzer-block key gets a targeted hint', () {
      const config = Config(unknownKeys: ['dartrics.language']);
      final issues = diagnose(config);
      expect(issues, hasLength(1));
      expect(issues.single.message, contains('"language"'));
      expect(issues.single.message, contains('dartrics ignores it'));
      expect(issues.single.hint, contains('`analyzer:`'));
    });

    test('unknown key close to a real key gets a did-you-mean hint', () {
      const config = Config(
        unknownKeys: [
          'dartrics.metric',
          'dartrics.unused.entrypoints',
          'dartrics.metrics.cyclomatic-complexity.warnings',
        ],
      );
      final issues = diagnose(config);
      expect(issues, hasLength(3));
      expect(issues[0].hint, contains('metrics'));
      expect(issues[1].hint, contains('entry-points'));
      expect(issues[2].hint, contains('warning'));
    });

    test('unknown key with no close match has no hint', () {
      const config = Config(unknownKeys: ['dartrics.zzzzzzzz']);
      final issues = diagnose(config);
      expect(issues, hasLength(1));
      expect(issues.single.hint, isNull);
    });

    test('multiple issues accumulate', () {
      const config = Config(
        metricThresholds: {
          'cyclomatic-complexity': MetricThresholds(warning: 20, error: 10),
          'cylomatic-complexity': MetricThresholds(warning: 1),
        },
      );
      final issues = diagnose(config);
      expect(issues, hasLength(2));
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

    test('exits 1 on a misplaced analyzer language block', () async {
      final f = File('${dir.path}/analysis_options.yaml');
      await f.writeAsString('''
dartrics:
  language:
    strict-casts: true
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
