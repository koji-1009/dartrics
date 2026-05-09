import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dartrics/src/config/config.dart';
import 'package:dartrics/src/unused/unused_detector.dart';
import 'package:test/test.dart';

UnusedSource _src(String path, String content) {
  final result = parseString(content: content);
  return (path: path, unit: result.unit, lineInfo: result.lineInfo);
}

void main() {
  // Every codegen-keep-alive annotation is honored unconditionally;
  // these tests pin that always-on behaviour for each ecosystem.

  test(
    '@freezed-annotated classes stay alive without explicit opt-in',
    () async {
      final unused = await const UnusedDetector().detect([
        _src('/proj/lib/src/model.dart', '''
class Freezed { const Freezed(); }
const freezed = Freezed();

@freezed
class Foo {}

class Bar {}

void main() {}
'''),
      ], const UnusedConfig(excludeExported: false));
      final names = unused.map((u) => u.name).toSet();
      expect(names, isNot(contains('Foo')));
      expect(names, contains('Bar'));
    },
  );

  test(
    '@TypedGoRoute-annotated classes stay alive without explicit opt-in',
    () async {
      final unused = await const UnusedDetector().detect([
        _src('/proj/lib/src/router.dart', '''
class TypedGoRoute<T> { const TypedGoRoute(); }

@TypedGoRoute<HomeScreen>()
class HomeScreenRoute {}

class HomeScreen {}

class UnusedScreen {}

void main() {}
'''),
      ], const UnusedConfig(excludeExported: false));
      final names = unused.map((u) => u.name).toSet();
      expect(names, isNot(contains('HomeScreenRoute')));
      expect(names, contains('UnusedScreen'));
    },
  );

  test('@MappableClass stays alive (dart_mappable)', () async {
    final unused = await const UnusedDetector().detect([
      _src('/proj/lib/src/model.dart', '''
class MappableClass { const MappableClass(); }

@MappableClass()
class Foo {}

void main() {}
'''),
    ], const UnusedConfig(excludeExported: false));
    expect(unused.map((u) => u.name).toSet(), isNot(contains('Foo')));
  });

  test('@riverpod-annotated providers stay alive', () async {
    final unused = await const UnusedDetector().detect([
      _src('/proj/lib/src/providers.dart', '''
class Riverpod { const Riverpod(); }
const riverpod = Riverpod();

@riverpod
class Counter {}

void main() {}
'''),
    ], const UnusedConfig(excludeExported: false));
    expect(unused.map((u) => u.name).toSet(), isNot(contains('Counter')));
  });

  test('@injectable-annotated classes stay alive', () async {
    final unused = await const UnusedDetector().detect([
      _src('/proj/lib/src/services.dart', '''
class Injectable { const Injectable(); }
const injectable = Injectable();

@injectable
class AuthService {}

void main() {}
'''),
    ], const UnusedConfig(excludeExported: false));
    expect(unused.map((u) => u.name).toSet(), isNot(contains('AuthService')));
  });

  test('@HiveType-annotated models stay alive', () async {
    final unused = await const UnusedDetector().detect([
      _src('/proj/lib/src/models.dart', '''
class HiveType { const HiveType({required this.typeId}); final int typeId; }

@HiveType(typeId: 0)
class UserBox {}

void main() {}
'''),
    ], const UnusedConfig(excludeExported: false));
    expect(unused.map((u) => u.name).toSet(), isNot(contains('UserBox')));
  });

  test('@DriftDatabase-annotated classes stay alive', () async {
    final unused = await const UnusedDetector().detect([
      _src('/proj/lib/src/database.dart', '''
class DriftDatabase { const DriftDatabase({this.tables}); final List? tables; }

@DriftDatabase()
class AppDatabase {}

void main() {}
'''),
    ], const UnusedConfig(excludeExported: false));
    expect(unused.map((u) => u.name).toSet(), isNot(contains('AppDatabase')));
  });

  test(
    'legacy `presets:` field is accepted but no longer narrows the set',
    () async {
      // Even with an empty (or wrong) `presets:` list, freezed-annotated
      // classes still stay alive — the preset-opt-in mechanism is a no-op
      // for backward compatibility only.
      final unused = await const UnusedDetector().detect([
        _src('/proj/lib/src/model.dart', '''
class Freezed { const Freezed(); }
const freezed = Freezed();

@freezed
class Foo {}

void main() {}
'''),
      ], const UnusedConfig(excludeExported: false, presets: []));
      expect(unused.map((u) => u.name).toSet(), isNot(contains('Foo')));
    },
  );
}
