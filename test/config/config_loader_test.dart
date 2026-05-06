import 'dart:io';

import 'package:dartrics/src/config/config_loader.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('config_test_');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('returns defaults when file does not exist', () async {
    final config = await loadConfig('${dir.path}/missing.yaml');
    expect(config.metricThresholds, isEmpty);
    expect(config.exclude, isEmpty);
    expect(config.unused.entryPoints, contains('main'));
  });

  test('returns defaults when YAML root is not a map', () async {
    final f = File('${dir.path}/scalar.yaml');
    await f.writeAsString('"just a string"\n');
    final config = await loadConfig(f.path);
    expect(config.metricThresholds, isEmpty);
  });

  test('returns defaults when no `dartrics` section is present', () async {
    final f = File('${dir.path}/other.yaml');
    await f.writeAsString('analyzer:\n  exclude: []\n');
    final config = await loadConfig(f.path);
    expect(config.metricThresholds, isEmpty);
  });

  test(
    'parses metric thresholds, exclude globs, and unused settings',
    () async {
      final f = File('${dir.path}/full.yaml');
      await f.writeAsString('''
dartrics:
  metrics:
    cyclomatic-complexity:
      warning: 10
      error: 20
    cognitive-complexity: 15
  unused:
    entry-points:
      - main
      - bootstrap
    exclude-exported: false
    ignore-annotations:
      - keepalive
  exclude:
    - "lib/generated/**"
''');
      final config = await loadConfig(f.path);
      expect(config.metricThresholds['cyclomatic-complexity']?.warning, 10);
      expect(config.metricThresholds['cyclomatic-complexity']?.error, 20);
      expect(config.metricThresholds['cognitive-complexity']?.warning, 15);
      expect(config.unused.entryPoints, ['main', 'bootstrap']);
      expect(config.unused.excludeExported, isFalse);
      expect(config.unused.ignoreAnnotations, ['keepalive']);
      expect(config.exclude, ['lib/generated/**']);
    },
  );

  test('metrics map accepts bool short-form to toggle `enabled`', () async {
    final f = File('${dir.path}/enable.yaml');
    await f.writeAsString('''
dartrics:
  metrics:
    halstead-volume: true
    cognitive-complexity: false
''');
    final config = await loadConfig(f.path);
    expect(config.metricThresholds['halstead-volume']?.enabled, isTrue);
    expect(config.metricThresholds['cognitive-complexity']?.enabled, isFalse);
  });

  test('metrics map accepts the long form with enabled + thresholds', () async {
    final f = File('${dir.path}/long.yaml');
    await f.writeAsString('''
dartrics:
  metrics:
    halstead-volume:
      enabled: true
      warning: 1000
''');
    final config = await loadConfig(f.path);
    final t = config.metricThresholds['halstead-volume'];
    expect(t?.enabled, isTrue);
    expect(t?.warning, 1000);
  });

  test('parses unused.presets list', () async {
    final f = File('${dir.path}/presets.yaml');
    await f.writeAsString('''
dartrics:
  unused:
    presets:
      - freezed
      - json_serializable
''');
    final config = await loadConfig(f.path);
    expect(config.unused.presets, ['freezed', 'json_serializable']);
  });

  test('throws ConfigException on malformed YAML', () async {
    final f = File('${dir.path}/broken.yaml');
    await f.writeAsString('dartrics:\n  metrics:\n    {broken\n');
    await expectLater(loadConfig(f.path), throwsA(isA<ConfigException>()));
  });

  test('parses the flutter flag', () async {
    final f = File('${dir.path}/flutter.yaml');
    await f.writeAsString('dartrics:\n  flutter: true\n');
    final config = await loadConfig(f.path);
    expect(config.flutter, isTrue);
  });
}
