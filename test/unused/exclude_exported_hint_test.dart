import 'dart:io';

import 'package:dartrics/src/config/config.dart';
import 'package:dartrics/src/unused/exclude_exported_hint.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('exclude_exported_hint_');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<void> writePubspec(String body) =>
      File('${dir.path}/pubspec.yaml').writeAsString(body);

  String? hint({
    UnusedConfig config = const UnusedConfig(),
    int findingCount = 0,
  }) => excludeExportedAppHint(
    root: dir.path,
    config: config,
    findingCount: findingCount,
  );

  test('fires on an empty run of an unpublished package', () async {
    await writePubspec('name: app\npublish_to: none\n');
    expect(hint(), contains('exclude-exported: false'));
  });

  test('stays silent when the run found something', () async {
    await writePubspec('name: app\npublish_to: none\n');
    expect(hint(findingCount: 1), isNull);
  });

  test('stays silent when exclude-exported is already off', () async {
    await writePubspec('name: app\npublish_to: none\n');
    expect(hint(config: const UnusedConfig(excludeExported: false)), isNull);
  });

  test('stays silent for a publishable package', () async {
    await writePubspec('name: pkg\n');
    expect(hint(), isNull);
  });

  test('stays silent without a pubspec.yaml', () {
    expect(hint(), isNull);
  });

  test('stays silent on a pubspec.yaml that does not parse', () async {
    await writePubspec('name: [unclosed\n');
    expect(hint(), isNull);
  });

  test(
    'writeExcludeExportedAppHint writes the line only when it fires',
    () async {
      await writePubspec('name: app\npublish_to: none\n');
      final fired = StringBuffer();
      writeExcludeExportedAppHint(
        fired,
        root: dir.path,
        config: const UnusedConfig(),
        findingCount: 0,
      );
      expect(fired.toString(), contains('publish_to: none'));
      final silent = StringBuffer();
      writeExcludeExportedAppHint(
        silent,
        root: dir.path,
        config: const UnusedConfig(),
        findingCount: 1,
      );
      expect(silent.toString(), isEmpty);
    },
  );
}
