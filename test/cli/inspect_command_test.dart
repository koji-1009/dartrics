import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('inspect_cli_');
    await Directory('${dir.path}/lib').create(recursive: true);
    await File('${dir.path}/lib/foo.dart').writeAsString('''
void main() {
  caller();
}

void caller() {
  target();
  target();
}

void target() {}
''');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test(
    'json output carries query echo, depth, direction, and the subgraph',
    () async {
      final out = File('${dir.path}/inspect.json');
      final result = await runCaptured([
        'inspect',
        'target',
        '--root',
        '${dir.path}/lib',
        '--depth',
        '2',
        '--direction',
        'up',
        '--reporter',
        'json',
        '--output',
        out.path,
        '--config',
        '${dir.path}/no.yaml',
      ]);
      expect(result.exitCode, 0);
      final body = jsonDecode(out.readAsStringSync()) as Map<String, Object?>;
      expect(body['query'], 'target');
      expect(body['depth'], 2);
      expect(body['direction'], 'up');
      final matches = (body['matches']! as List).cast<Map<String, Object?>>();
      expect(matches, hasLength(1));
      final anchor = matches.first['anchor']! as Map<String, Object?>;
      final scope = anchor['scope']! as Map<String, Object?>;
      expect(scope['name'], 'target');
      final upstream = (matches.first['upstream']! as List)
          .cast<Map<String, Object?>>();
      expect(upstream.map((n) => n['depth']), [1, 2]);
    },
  );

  test('ai output carries the reference-only framing comments', () async {
    final out = File('${dir.path}/inspect.yaml');
    final result = await runCaptured([
      'inspect',
      'target',
      '--root',
      '${dir.path}/lib',
      '--depth',
      '1',
      '--reporter',
      'ai',
      '--output',
      out.path,
      '--config',
      '${dir.path}/no.yaml',
    ]);
    expect(result.exitCode, 0);
    final body = out.readAsStringSync();
    expect(body, contains('# dartrics inspect-report v1'));
    expect(body, contains('reference information'));
    expect(body, contains('query: target'));
    expect(body, contains('scope: target'));
  });

  test('rejects invocations that omit the symbol argument', () async {
    final result = await runCaptured([
      'inspect',
      '--root',
      '${dir.path}/lib',
      '--config',
      '${dir.path}/no.yaml',
    ]);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('exactly one symbol'));
  });

  test('rejects depth < 1', () async {
    final result = await runCaptured([
      'inspect',
      'target',
      '--root',
      '${dir.path}/lib',
      '--depth',
      '0',
      '--config',
      '${dir.path}/no.yaml',
    ]);
    expect(result.exitCode, isNot(0));
  });
}
