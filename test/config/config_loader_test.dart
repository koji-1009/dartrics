import 'dart:io';

import 'package:dartrics/src/config/config.dart';
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

  test('flutter and test default to true when omitted', () async {
    final f = File('${dir.path}/empty.yaml');
    await f.writeAsString('dartrics:\n  metrics: {}\n');
    final config = await loadConfig(f.path);
    expect(config.flutter, isTrue);
    expect(config.test, isTrue);
  });

  test('parses the test flag', () async {
    final f = File('${dir.path}/test.yaml');
    await f.writeAsString('dartrics:\n  test: false\n');
    final config = await loadConfig(f.path);
    expect(config.test, isFalse);
  });

  test('parses snapshot section with mode + path', () async {
    final f = File('${dir.path}/snap.yaml');
    await f.writeAsString('''
dartrics:
  snapshot:
    mode: baseline
    path: custom-snap.json
''');
    final config = await loadConfig(f.path);
    expect(config.snapshot.mode, SnapshotMode.baseline);
    expect(config.snapshot.path, 'custom-snap.json');
  });

  test('snapshot accepts a bare string mode', () async {
    final f = File('${dir.path}/snap-string.yaml');
    await f.writeAsString('dartrics:\n  snapshot: cache\n');
    final config = await loadConfig(f.path);
    expect(config.snapshot.mode, SnapshotMode.cache);
    expect(config.snapshot.path, isNull);
  });

  test('snapshot accepts a bool toggle', () async {
    final f = File('${dir.path}/snap-bool.yaml');
    await f.writeAsString('dartrics:\n  snapshot: false\n');
    final config = await loadConfig(f.path);
    expect(config.snapshot.mode, SnapshotMode.none);
  });

  test('rejects unknown snapshot modes with ConfigException', () async {
    final f = File('${dir.path}/snap-bogus.yaml');
    await f.writeAsString('dartrics:\n  snapshot: bogus\n');
    await expectLater(loadConfig(f.path), throwsA(isA<ConfigException>()));
  });

  test('snapshot map without a mode falls back to cache', () async {
    final f = File('${dir.path}/snap-empty.yaml');
    await f.writeAsString('dartrics:\n  snapshot: {}\n');
    final config = await loadConfig(f.path);
    expect(config.snapshot.mode, SnapshotMode.cache);
  });

  group('dismissals', () {
    test('absent block leaves both sources off', () async {
      final f = File('${dir.path}/no-dismiss.yaml');
      await f.writeAsString('dartrics:\n  flutter: false\n');
      final config = await loadConfig(f.path);
      expect(config.dismissals.commentSource, isFalse);
      expect(config.dismissals.yamlSource, isFalse);
      expect(config.dismissals.enabled, isFalse);
    });

    test('bare block enables both sources with defaults', () async {
      final f = File('${dir.path}/bare-dismiss.yaml');
      await f.writeAsString('dartrics:\n  dismissals: {}\n');
      final config = await loadConfig(f.path);
      expect(config.dismissals.commentSource, isTrue);
      expect(config.dismissals.yamlSource, isTrue);
      expect(config.dismissals.requireReason, isTrue);
      expect(config.dismissals.minReasonLength, 20);
      expect(config.dismissals.requireAuthor, isFalse);
      expect(config.dismissals.requireTimestamp, isFalse);
      expect(config.dismissals.yamlPath, isNull);
    });

    test('granular sources + knobs round-trip', () async {
      final f = File('${dir.path}/granular.yaml');
      await f.writeAsString('''
dartrics:
  dismissals:
    sources:
      comment: false
      yaml: true
    requireReason: false
    minReasonLength: 5
    requireAuthor: true
    requireTimestamp: true
    yamlPath: custom.yaml
''');
      final config = await loadConfig(f.path);
      expect(config.dismissals.commentSource, isFalse);
      expect(config.dismissals.yamlSource, isTrue);
      expect(config.dismissals.requireReason, isFalse);
      expect(config.dismissals.minReasonLength, 5);
      expect(config.dismissals.requireAuthor, isTrue);
      expect(config.dismissals.requireTimestamp, isTrue);
      expect(config.dismissals.yamlPath, 'custom.yaml');
    });

    test('rejects when both sources are disabled', () async {
      final f = File('${dir.path}/no-source.yaml');
      await f.writeAsString('''
dartrics:
  dismissals:
    sources:
      comment: false
      yaml: false
''');
      await expectLater(
        loadConfig(f.path),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.message,
            'message',
            contains('at least one dismissal source must be enabled'),
          ),
        ),
      );
    });

    test('rejects negative minReasonLength', () async {
      final f = File('${dir.path}/neg-len.yaml');
      await f.writeAsString('''
dartrics:
  dismissals:
    minReasonLength: -1
''');
      await expectLater(
        loadConfig(f.path),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.message,
            'message',
            contains('minReasonLength must be non-negative'),
          ),
        ),
      );
    });

    test('rejects requireAuthor without yaml source', () async {
      final f = File('${dir.path}/author-no-yaml.yaml');
      await f.writeAsString('''
dartrics:
  dismissals:
    sources:
      comment: true
      yaml: false
    requireAuthor: true
''');
      await expectLater(
        loadConfig(f.path),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.message,
            'message',
            contains('requireAuthor needs sources.yaml: true'),
          ),
        ),
      );
    });

    test('rejects requireTimestamp without yaml source', () async {
      final f = File('${dir.path}/ts-no-yaml.yaml');
      await f.writeAsString('''
dartrics:
  dismissals:
    sources:
      comment: true
      yaml: false
    requireTimestamp: true
''');
      await expectLater(
        loadConfig(f.path),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.message,
            'message',
            contains('requireTimestamp needs sources.yaml: true'),
          ),
        ),
      );
    });

    test('rejects non-map dismissals node', () async {
      final f = File('${dir.path}/scalar-dismiss.yaml');
      await f.writeAsString('dartrics:\n  dismissals: nope\n');
      await expectLater(
        loadConfig(f.path),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.message,
            'message',
            contains('dartrics.dismissals must be a map'),
          ),
        ),
      );
    });

    test('rejects non-map sources node', () async {
      final f = File('${dir.path}/scalar-sources.yaml');
      await f.writeAsString('''
dartrics:
  dismissals:
    sources: yaml
''');
      await expectLater(
        loadConfig(f.path),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.message,
            'message',
            contains('dartrics.dismissals.sources must be a map'),
          ),
        ),
      );
    });
  });
}
