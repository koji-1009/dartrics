import 'dart:convert';
import 'dart:io';

import 'package:io/io.dart' show ExitCode;
import 'package:test/test.dart';

import 'helpers.dart';

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
    final code = await runQuietly([
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

  test('stale YAML dismissal surfaces in JSON staleDismissals block', () async {
    // Write a clean source file with no violations of any kind.
    await File('${dir.path}/lib/foo.dart').writeAsString('''
int simple() => 1;
''');
    await File('${dir.path}/dartrics-dismissals.yaml').writeAsString('''
version: 1
dismissals:
  - file: ${dir.path}/lib/foo.dart
    scope: gone
    metric: cyclomatic-complexity
    reason: "scope was renamed last refactor; keeping the entry by mistake"
''');
    final config = await writeConfig('''
dartrics:
  dismissals:
    sources:
      comment: false
      yaml: true
    yamlPath: ${dir.path}/dartrics-dismissals.yaml
''');
    final body = await runAnalyzeAsJson(config: config);
    expect(body.containsKey('staleDismissals'), isTrue);
    final stale =
        (body['staleDismissals'] as List).single as Map<String, dynamic>;
    expect(stale['scope'], 'gone');
    expect(stale['metric'], 'cyclomatic-complexity');
    expect(stale['source'], 'yaml');
    expect(stale['reason'], contains('renamed'));
  });

  test('warnStale: false suppresses the staleDismissals block', () async {
    await File(
      '${dir.path}/lib/foo.dart',
    ).writeAsString('int simple() => 1;\n');
    await File('${dir.path}/dartrics-dismissals.yaml').writeAsString('''
version: 1
dismissals:
  - file: ${dir.path}/lib/foo.dart
    scope: gone
    metric: cyclomatic-complexity
    reason: "this entry is stale but the project disabled the warning"
''');
    final config = await writeConfig('''
dartrics:
  dismissals:
    sources:
      comment: false
      yaml: true
    warnStale: false
    yamlPath: ${dir.path}/dartrics-dismissals.yaml
''');
    final body = await runAnalyzeAsJson(config: config);
    expect(body.containsKey('staleDismissals'), isFalse);
  });

  test(
    'stale entries for unanalyzed files (--since filter) are not reported',
    () async {
      // The dismiss target is for a file that wasn't actually analyzed
      // because there's no source backing it; the engine never queries
      // the index for that file, but the file path also isn't in the
      // analyzedPaths set. The warning logic must skip it so AI loops
      // don't get false-positive cleanup proposals on files outside
      // the current diff scope.
      await File(
        '${dir.path}/lib/foo.dart',
      ).writeAsString('int simple() => 1;\n');
      await File('${dir.path}/dartrics-dismissals.yaml').writeAsString('''
version: 1
dismissals:
  - file: lib/elsewhere.dart
    scope: notAnalyzed
    metric: cyclomatic-complexity
    reason: "elsewhere.dart isn't in the analyzed file set this run"
''');
      final config = await writeConfig('''
dartrics:
  dismissals:
    sources:
      comment: false
      yaml: true
    yamlPath: ${dir.path}/dartrics-dismissals.yaml
''');
      final body = await runAnalyzeAsJson(config: config);
      // The engine analyzed lib/foo.dart only — lib/elsewhere.dart was
      // never measured, so the dismiss isn't actually stale, just not
      // observed. The staleDismissals block stays empty.
      expect(body.containsKey('staleDismissals'), isFalse);
    },
  );

  test(
    'stray `// dartrics:dismiss` comment surfaces stderr WARN when commentSource is off',
    () async {
      // The dismiss block itself is missing — both sources default to
      // disabled at the config layer. Without the WARN the comment
      // would be a silent no-op, exactly the failure mode the dismiss
      // channel is built to prevent.
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
''');
      final out = File('${dir.path}/out.json');
      final captured = await runCaptured([
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
      ]);
      expect(captured.exitCode, 0);
      expect(captured.stderr, contains('dartrics:dismiss'));
      expect(captured.stderr, contains('commentSource is disabled'));
      expect(captured.stderr, contains('sources: [comment]'));
      // The comment really is being ignored — the violation should
      // still fire as a regular non-dismissed entry.
      final body = jsonDecode(out.readAsStringSync()) as Map<String, dynamic>;
      final v = _findViolation(body, 'branchy', 'cyclomatic-complexity');
      expect(v.containsKey('dismissed'), isFalse);
    },
  );

  test('commentSource enabled: stray-comment WARN does not fire', () async {
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
    final out = File('${dir.path}/out.json');
    final captured = await runCaptured([
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
    ]);
    expect(captured.exitCode, 0);
    expect(captured.stderr, isNot(contains('commentSource is disabled')));
  });

  test('stray-comment WARN aggregates across multiple files', () async {
    // Two files with stray dismiss comments → the WARN renders the
    // `+N more` suffix and the plural noun, exercising the multi-hit
    // branches that the single-file test cannot reach.
    await File('${dir.path}/lib/foo.dart').writeAsString('''
// dartrics:dismiss cyclomatic-complexity reason="state machine; splits hide intent"
int branchy(int x) => x;
''');
    await File('${dir.path}/lib/bar.dart').writeAsString('''
// dartrics:dismiss cyclomatic-complexity reason="state machine; splits hide intent"
int alsoBranchy(int x) => x;
''');
    final config = await writeConfig('''
dartrics:
  metrics:
    cyclomatic-complexity:
      warning: 1
''');
    final out = File('${dir.path}/out.json');
    final captured = await runCaptured([
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
    ]);
    expect(captured.exitCode, 0);
    expect(captured.stderr, contains('2 files'));
    expect(captured.stderr, contains('+1 more'));
  });

  test('--strict-dismiss suppresses the stray-comment WARN', () async {
    // `--strict-dismiss` is the audit mode — the operator deliberately
    // wants every dismissal ignored. Surfacing the WARN there would
    // be noise.
    await File('${dir.path}/lib/foo.dart').writeAsString('''
// dartrics:dismiss cyclomatic-complexity reason="state machine: splits hide intent"
int branchy(int x) => x;
''');
    final config = await writeConfig('''
dartrics:
  metrics:
    cyclomatic-complexity:
      warning: 1
''');
    final out = File('${dir.path}/out.json');
    final captured = await runCaptured([
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
      '--strict-dismiss',
    ]);
    expect(captured.exitCode, 0);
    expect(captured.stderr, isNot(contains('commentSource is disabled')));
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
    final code = await runAppQuietly([
      'analyze',
      dir.path,
      '--config',
      config.path,
    ]);
    expect(code, ExitCode.config.code);
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
