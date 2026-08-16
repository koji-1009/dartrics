import 'dart:convert';
import 'dart:io';

import 'package:dartrics/src/regression/package_config_seed.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('rewritePackageConfig', () {
    late Directory repoTop;

    setUp(() async {
      final raw = await Directory.systemTemp.createTemp('pkg_config_seed_');
      repoTop = Directory(raw.resolveSymbolicLinksSync());
    });

    tearDown(() async {
      await repoTop.delete(recursive: true);
    });

    String rewrite(String raw) => rewritePackageConfig(
      raw,
      sourceDir: p.join(repoTop.path, '.dart_tool'),
      repoTop: repoTop.path,
    );

    test('keeps relative rootUris that resolve inside the repository', () {
      final raw = jsonEncode({
        'configVersion': 2,
        'packages': [
          {'name': 'self', 'rootUri': '../', 'packageUri': 'lib/'},
          {'name': 'member', 'rootUri': '../pkgs/member', 'packageUri': 'lib/'},
        ],
      });
      expect(rewrite(raw), raw);
    });

    test('rewrites relative rootUris escaping the repository to absolute '
        'URIs anchored at the original location', () {
      final raw = jsonEncode({
        'packages': [
          {'name': 'sibling', 'rootUri': '../../sibling', 'packageUri': 'lib/'},
        ],
      });
      final out = jsonDecode(rewrite(raw)) as Map<String, Object?>;
      final pkg = (out['packages']! as List).first as Map<String, Object?>;
      expect(
        pkg['rootUri'],
        p.toUri(p.join(p.dirname(repoTop.path), 'sibling')).toString(),
      );
    });

    test('leaves absolute (pub-cache style) rootUris untouched', () {
      final raw = jsonEncode({
        'packages': [
          {'name': 'dep', 'rootUri': 'file:///pub-cache/dep-1.0.0'},
        ],
      });
      expect(rewrite(raw), raw);
    });

    test('leaves entries with a missing, non-string, or unparsable '
        'rootUri untouched', () {
      final raw = jsonEncode({
        'packages': [
          {'name': 'no-root'},
          {'name': 'numeric-root', 'rootUri': 5},
          {'name': 'bad-uri', 'rootUri': ':'},
          'not-a-map',
        ],
      });
      expect(rewrite(raw), raw);
    });

    test('returns content that is not the expected JSON shape verbatim', () {
      expect(rewrite('not json'), 'not json');
      expect(rewrite('[1, 2]'), '[1, 2]');
      expect(rewrite('{"packages": 3}'), '{"packages": 3}');
    });
  });

  group('seedWorktreePackageConfig', () {
    late Directory tmp;

    setUp(() async {
      final raw = await Directory.systemTemp.createTemp('pkg_config_seed_io_');
      tmp = Directory(raw.resolveSymbolicLinksSync());
    });

    tearDown(() async {
      await tmp.delete(recursive: true);
    });

    test('writes the rewritten config into the target .dart_tool', () async {
      final sourceRoot = p.join(tmp.path, 'source');
      final targetRoot = p.join(tmp.path, 'target');
      final config = jsonEncode({
        'configVersion': 2,
        'packages': [
          {'name': 'self', 'rootUri': '../', 'packageUri': 'lib/'},
        ],
      });
      File(p.join(sourceRoot, '.dart_tool', 'package_config.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(config);
      seedWorktreePackageConfig(
        sourceRoot: sourceRoot,
        targetRoot: targetRoot,
        repoTop: sourceRoot,
      );
      expect(
        File(p.join(targetRoot, '.dart_tool', 'package_config.json'))
            .readAsStringSync(),
        config,
      );
    });

    test('does nothing when the source has no package_config.json', () async {
      final sourceRoot = p.join(tmp.path, 'source');
      final targetRoot = p.join(tmp.path, 'target');
      Directory(sourceRoot).createSync(recursive: true);
      seedWorktreePackageConfig(
        sourceRoot: sourceRoot,
        targetRoot: targetRoot,
        repoTop: sourceRoot,
      );
      expect(Directory(targetRoot).existsSync(), isFalse);
    });
  });
}
