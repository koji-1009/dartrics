import 'dart:io';

import 'package:dartrics/src/config/config_loader.dart';
import 'package:dartrics/src/dismiss/dismissal.dart';
import 'package:dartrics/src/dismiss/yaml_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('yaml_dismiss_');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<File> write(String yaml, {String name = 'd.yaml'}) async {
    final f = File('${dir.path}/$name');
    await f.writeAsString(yaml);
    return f;
  }

  test('returns empty list when sidecar is absent', () {
    expect(
      loadYamlDismissals('${dir.path}/missing.yaml', root: dir.path),
      isEmpty,
    );
  });

  test('parses a fully-specified entry with by + at', () async {
    final f = await write('''
version: 1
dismissals:
  - file: lib/parser.dart
    scope: parse
    metric: cyclomatic-complexity
    reason: "Recursive descent parser"
    by: claude-opus-4-7
    at: "2026-05-06T19:14:00Z"
''');
    final dismissals = loadYamlDismissals(f.path, root: dir.path);
    expect(dismissals, hasLength(1));
    final d = dismissals.single;
    expect(d.file, p.normalize(p.join(dir.path, 'lib/parser.dart')));
    expect(d.scope, 'parse');
    expect(d.metricId, 'cyclomatic-complexity');
    expect(d.reason, 'Recursive descent parser');
    expect(d.by, 'claude-opus-4-7');
    expect(d.at, DateTime.utc(2026, 5, 6, 19, 14, 0));
    expect(d.source, DismissalSource.yaml);
  });

  test('accepts entries without optional fields', () async {
    final f = await write('''
version: 1
dismissals:
  - file: a.dart
    scope: fn
    metric: method-length
''');
    final d = loadYamlDismissals(f.path, root: dir.path).single;
    expect(d.reason, '');
    expect(d.by, isNull);
    expect(d.at, isNull);
  });

  test('rejects unsupported version', () async {
    final f = await write('''
version: 2
dismissals: []
''');
    expect(
      () => loadYamlDismissals(f.path, root: dir.path),
      throwsA(
        isA<ConfigException>().having(
          (e) => e.message,
          'message',
          contains('unsupported version "2"'),
        ),
      ),
    );
  });

  test('rejects non-map root', () async {
    final f = await write('"just a string"\n');
    expect(
      () => loadYamlDismissals(f.path, root: dir.path),
      throwsA(
        isA<ConfigException>().having(
          (e) => e.message,
          'message',
          contains('top-level YAML must be a map'),
        ),
      ),
    );
  });

  test('rejects non-list dismissals', () async {
    final f = await write('''
version: 1
dismissals: nope
''');
    expect(
      () => loadYamlDismissals(f.path, root: dir.path),
      throwsA(
        isA<ConfigException>().having(
          (e) => e.message,
          'message',
          contains('`dismissals` must be a list'),
        ),
      ),
    );
  });

  test('returns empty when dismissals key is omitted', () async {
    final f = await write('version: 1\n');
    expect(loadYamlDismissals(f.path, root: dir.path), isEmpty);
  });

  test('rejects malformed entries', () async {
    final f = await write('''
version: 1
dismissals:
  - "not a map"
''');
    expect(
      () => loadYamlDismissals(f.path, root: dir.path),
      throwsA(
        isA<ConfigException>().having(
          (e) => e.message,
          'message',
          contains('dismissals[0] must be a map'),
        ),
      ),
    );
  });

  test('rejects entries missing file', () async {
    final f = await write('''
version: 1
dismissals:
  - scope: fn
    metric: cc
''');
    expect(
      () => loadYamlDismissals(f.path, root: dir.path),
      throwsA(
        isA<ConfigException>().having(
          (e) => e.message,
          'message',
          contains('dismissals[0].file is required'),
        ),
      ),
    );
  });

  test('rejects entries missing scope', () async {
    final f = await write('''
version: 1
dismissals:
  - file: a.dart
    metric: cc
''');
    expect(
      () => loadYamlDismissals(f.path, root: dir.path),
      throwsA(
        isA<ConfigException>().having(
          (e) => e.message,
          'message',
          contains('dismissals[0].scope is required'),
        ),
      ),
    );
  });

  test('rejects entries missing metric', () async {
    final f = await write('''
version: 1
dismissals:
  - file: a.dart
    scope: fn
''');
    expect(
      () => loadYamlDismissals(f.path, root: dir.path),
      throwsA(
        isA<ConfigException>().having(
          (e) => e.message,
          'message',
          contains('dismissals[0].metric is required'),
        ),
      ),
    );
  });

  test('rejects entries with unparsable at', () async {
    final f = await write('''
version: 1
dismissals:
  - file: a.dart
    scope: fn
    metric: cc
    at: "not-a-time"
''');
    expect(
      () => loadYamlDismissals(f.path, root: dir.path),
      throwsA(
        isA<ConfigException>().having(
          (e) => e.message,
          'message',
          contains('not a valid ISO-8601 timestamp'),
        ),
      ),
    );
  });

  test('rejects entries with non-string non-DateTime at', () async {
    final f = await write('''
version: 1
dismissals:
  - file: a.dart
    scope: fn
    metric: cc
    at: 12345
''');
    expect(
      () => loadYamlDismissals(f.path, root: dir.path),
      throwsA(
        isA<ConfigException>().having(
          (e) => e.message,
          'message',
          contains('must be a string or timestamp'),
        ),
      ),
    );
  });

  test('resolves a relative file against the analysis root', () async {
    final f = await write('''
version: 1
dismissals:
  - file: lib/a.dart
    scope: fn
    metric: method-length
''');
    final d = loadYamlDismissals(f.path, root: dir.path).single;
    expect(p.isAbsolute(d.file), isTrue);
    expect(d.file, p.normalize(p.join(dir.path, 'lib', 'a.dart')));
  });

  test('resolves a relative root against the cwd', () async {
    final f = await write('''
version: 1
dismissals:
  - file: lib/a.dart
    scope: fn
    metric: method-length
''');
    final d = loadYamlDismissals(f.path, root: '.').single;
    expect(d.file, p.normalize(p.absolute('lib', 'a.dart')));
  });

  test('keeps an absolute file entry as-is', () async {
    final absolute = p.join(dir.path, 'lib', 'b.dart');
    final f = await write('''
version: 1
dismissals:
  - file: "$absolute"
    scope: fn
    metric: method-length
''');
    final d = loadYamlDismissals(f.path, root: dir.path).single;
    expect(d.file, p.normalize(absolute));
  });

  test('rejects malformed YAML', () async {
    final f = await write('version: 1\ndismissals:\n  - {broken\n');
    expect(
      () => loadYamlDismissals(f.path, root: dir.path),
      throwsA(
        isA<ConfigException>().having(
          (e) => e.message,
          'message',
          contains('failed to parse'),
        ),
      ),
    );
  });
}
