import 'dart:convert';
import 'dart:io';

import 'package:dartrics/src/cli/runner.dart';
import 'package:dartrics/src/entry_point.dart';
import 'package:io/io.dart' show ExitCode;
import 'package:test/test.dart';

/// End-to-end exercises for the `dartrics:dismiss` channel — comment
/// directive, YAML sidecar, validation gates, and `--strict-dismiss`.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dismiss_cli_');
    await Directory('${dir.path}/lib').create(recursive: true);
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<File> writeConfig(String body, {String name = 'opts.yaml'}) async {
    final f = File('${dir.path}/$name');
    await f.writeAsString(body);
    return f;
  }

  Future<Map<String, dynamic>> runAnalyzeAsJson({
    required File config,
    List<String> extraArgs = const [],
  }) async {
    final out = File('${dir.path}/out.json');
    final code = await buildCommandRunner().run([
      'analyze',
      dir.path,
      '--reporter',
      'json',
      '--output',
      out.path,
      '--root',
      dir.path,
      '--config',
      config.path,
      ...extraArgs,
    ]);
    expect(code, 0, reason: 'analyze exited non-zero');
    return jsonDecode(out.readAsStringSync()) as Map<String, dynamic>;
  }

  test('comment dismissal lands as dismissed=true on the violation', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
// dartrics:dismiss cyclomatic-complexity reason="state machine: splits hide intent"
int branchy(int x) {
  if (x > 0) return 1;
  if (x < 0) return -1;
  if (x == 0) return 0;
  return 99;
}
''');
    final config = await writeConfig('''
dartrics:
  metrics:
    cyclomatic-complexity:
      warning: 1
  dismissals:
    sources:
      comment: true
      yaml: false
''');
    final body = await runAnalyzeAsJson(config: config);
    final v = _findViolation(body, 'branchy', 'cyclomatic-complexity');
    expect(v['dismissed'], isTrue);
    expect(v['dismissedFrom'], 'comment');
    expect(v['dismissReason'], contains('state machine'));
  });

  test('YAML sidecar dismissal is honoured', () async {
    final dartFile = '${dir.path}/lib/foo.dart';
    await File(dartFile).writeAsString('''
int branchy(int x) {
  if (x > 0) return 1;
  if (x < 0) return -1;
  if (x == 0) return 0;
  return 99;
}
''');
    await File('${dir.path}/dartrics-dismissals.yaml').writeAsString('''
version: 1
dismissals:
  - file: $dartFile
    scope: branchy
    metric: cyclomatic-complexity
    reason: "Switching on int values keeps the intent local"
    by: claude-opus-4-7
    at: "2026-05-06T19:14:00Z"
''');
    final config = await writeConfig('''
dartrics:
  metrics:
    cyclomatic-complexity:
      warning: 1
  dismissals:
    sources:
      comment: false
      yaml: true
''');
    final body = await runAnalyzeAsJson(config: config);
    final v = _findViolation(body, 'branchy', 'cyclomatic-complexity');
    expect(v['dismissed'], isTrue);
    expect(v['dismissedFrom'], 'yaml');
    expect(v['dismissedBy'], 'claude-opus-4-7');
    expect(v['dismissedAt'], '2026-05-06T19:14:00.000Z');
  });

  test(
    'reason that fails minReasonLength surfaces dismissalRejected',
    () async {
      await File('${dir.path}/lib/foo.dart').writeAsString('''
// dartrics:dismiss cyclomatic-complexity reason="short"
int branchy(int x) {
  if (x > 0) return 1;
  if (x < 0) return -1;
  if (x == 0) return 0;
  return 99;
}
''');
      final config = await writeConfig('''
dartrics:
  metrics:
    cyclomatic-complexity:
      warning: 1
  dismissals:
    sources:
      comment: true
      yaml: false
    minReasonLength: 20
''');
      final body = await runAnalyzeAsJson(config: config);
      final v = _findViolation(body, 'branchy', 'cyclomatic-complexity');
      expect(v.containsKey('dismissed'), isFalse);
      expect(v['dismissalRejected'], contains('reason too short'));
    },
  );

  test('--strict-dismiss bypasses every dismissal', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
// dartrics:dismiss cyclomatic-complexity reason="switching on ints keeps the intent local"
int branchy(int x) {
  if (x > 0) return 1;
  if (x < 0) return -1;
  if (x == 0) return 0;
  return 99;
}
''');
    final config = await writeConfig('''
dartrics:
  metrics:
    cyclomatic-complexity:
      warning: 1
  dismissals:
    sources:
      comment: true
      yaml: false
''');
    final body = await runAnalyzeAsJson(
      config: config,
      extraArgs: ['--strict-dismiss'],
    );
    final v = _findViolation(body, 'branchy', 'cyclomatic-complexity');
    expect(v.containsKey('dismissed'), isFalse);
    expect(v.containsKey('dismissalRejected'), isFalse);
  });

  test('config error: both sources disabled exits with EX_CONFIG', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('void main() {}\n');
    final config = await writeConfig('''
dartrics:
  dismissals:
    sources:
      comment: false
      yaml: false
''');
    final saved = exitCode;
    exitCode = 0;
    try {
      await runApp(['analyze', dir.path, '--config', config.path]);
      expect(exitCode, ExitCode.config.code);
    } finally {
      exitCode = saved;
    }
  });
}

Map<String, dynamic> _findViolation(
  Map<String, dynamic> report,
  String scope,
  String metric,
) {
  final metrics = report['metrics'] as List;
  for (final m in metrics) {
    final mMap = m as Map<String, dynamic>;
    final scopeName = (mMap['scope'] as Map)['name'];
    if (scopeName != scope) continue;
    for (final v in mMap['violations'] as List) {
      final vMap = v as Map<String, dynamic>;
      if (vMap['metric'] == metric) return vMap;
    }
  }
  fail('no violation $metric on $scope in report');
}
