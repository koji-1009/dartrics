import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dartrics/src/config/config.dart';
import 'package:dartrics/src/unused/unused_detector.dart';
import 'package:test/test.dart';

UnusedSource _src(String path, String content) {
  final result = parseString(content: content);
  return (path: path, unit: result.unit, lineInfo: result.lineInfo);
}

void main() {
  test('enabling the freezed preset keeps `@freezed`-annotated classes alive '
      'even with excludeExported: false', () async {
    final unused = await const UnusedDetector().detect([
      _src('/proj/lib/src/model.dart', '''
class Freezed { const Freezed(); }
const freezed = Freezed();

@freezed
class Foo {}

class Bar {}

void main() {}
'''),
    ], const UnusedConfig(excludeExported: false, presets: ['freezed']));
    final names = unused.map((u) => u.name).toSet();
    expect(names, isNot(contains('Foo')));
    expect(names, contains('Bar'));
  });

  test(
    'go_router_builder preset keeps @TypedGoRoute-annotated classes alive',
    () async {
      final unused = await const UnusedDetector().detect(
        [
          _src('/proj/lib/src/router.dart', '''
class TypedGoRoute<T> { const TypedGoRoute(); }

@TypedGoRoute<HomeScreen>()
class HomeScreenRoute {}

class HomeScreen {}

class UnusedScreen {}

void main() {}
'''),
        ],
        const UnusedConfig(
          excludeExported: false,
          presets: ['go_router_builder'],
        ),
      );
      final names = unused.map((u) => u.name).toSet();
      expect(names, isNot(contains('HomeScreenRoute')));
      expect(names, contains('UnusedScreen'));
    },
  );

  test('without the matching preset, the class is reported unused', () async {
    final unused = await const UnusedDetector().detect([
      _src('/proj/lib/src/model.dart', '''
class MappableClass { const MappableClass(); }
const _kAnnotation = MappableClass();

@_kAnnotation
class Foo {}

void main() {}
'''),
    ], const UnusedConfig(excludeExported: false));
    final names = unused.map((u) => u.name).toSet();
    expect(names, contains('Foo'));
  });
}
