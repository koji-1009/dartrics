import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dartrics/src/config/config.dart';
import 'package:dartrics/src/unused/unused_detector.dart';
import 'package:test/test.dart';

UnusedSource _src(String path, String content) {
  final result = parseString(content: content);
  return (path: path, unit: result.unit, lineInfo: result.lineInfo);
}

void main() {
  test('top-level function not referenced anywhere is reported', () async {
    final unused = await const UnusedDetector().detect(
      [
        _src('a.dart', '''
void usedHelper() {}
void unusedHelper() {}
void main() { usedHelper(); }
'''),
      ],
      const UnusedConfig(),
    );
    final names = unused.map((u) => u.name).toList();
    expect(names, contains('unusedHelper'));
    expect(names, isNot(contains('usedHelper')));
    expect(names, isNot(contains('main')));
  });

  test('@pragma("vm:entry-point") keeps a declaration alive', () async {
    final unused = await const UnusedDetector().detect(
      [
        _src('a.dart', '''
@pragma('vm:entry-point')
void exposed() {}
void main() {}
'''),
      ],
      const UnusedConfig(),
    );
    final names = unused.map((u) => u.name).toList();
    expect(names, isNot(contains('exposed')));
  });

  test('configured ignore-annotations suppress unused reports', () async {
    final unused = await const UnusedDetector().detect(
      [
        _src('a.dart', '''
import 'package:meta/meta.dart';

@visibleForTesting
void testOnly() {}
void main() {}
'''),
      ],
      const UnusedConfig(),
    );
    final names = unused.map((u) => u.name).toList();
    expect(names, isNot(contains('testOnly')));
  });

  test('cross-file references reach across the unit list', () async {
    final unused = await const UnusedDetector().detect(
      [
        _src('a.dart', '''
class A {}
class B {}
'''),
        _src('b.dart', '''
import 'a.dart';
A make() { return A(); }
void main() { make(); }
'''),
      ],
      const UnusedConfig(),
    );
    final names = unused.map((u) => u.name).toList();
    expect(names, contains('B'));
    expect(names, isNot(contains('A')));
    expect(names, isNot(contains('make')));
  });

  test('excludeExported: lib/ top-level declarations are roots, '
      'and exported `show` symbols keep src/ declarations alive', () async {
    final unused = await const UnusedDetector().detect(
      [
        _src('/proj/lib/api.dart', '''
export 'src/widget.dart' show Widget;
'''),
        _src('/proj/lib/src/widget.dart', '''
class Widget {}
class _Internal {}
class UnusedThing {}
'''),
      ],
      const UnusedConfig(excludeExported: true),
    );
    final names = unused.map((u) => u.name).toList();
    expect(names, contains('UnusedThing'));
    expect(names, isNot(contains('Widget')));
  });

  test('private (underscore-prefixed) names are not reported (analyzer covers them)',
      () async {
    final unused = await const UnusedDetector().detect(
      [
        _src('a.dart', '''
void _privateNeverCalled() {}
void main() {}
'''),
      ],
      const UnusedConfig(),
    );
    final names = unused.map((u) => u.name).toList();
    expect(names, isNot(contains('_privateNeverCalled')));
  });
}
