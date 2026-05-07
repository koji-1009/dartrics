import 'dart:io';

import 'package:dartrics/src/analyzer_runner.dart';
import 'package:dartrics/src/config/config.dart';
import 'package:dartrics/src/models/unused_declaration.dart';
import 'package:dartrics/src/unused/resolved_reachability.dart';
import 'package:dartrics/src/unused/unused_detector.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('resolved_unused_');
    await Directory('${dir.path}/lib/src').create(recursive: true);
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<List<ResolvedUnusedSource>> resolveAll() async {
    final runner = AnalyzerRunner(roots: ['${dir.path}/lib']);
    final units = await runner.resolveAll();
    return [for (final u in units) (path: u.path, unit: u.unit)];
  }

  Future<List<UnusedDeclaration>> detectIn(UnusedConfig config) async {
    final sources = await resolveAll();
    return const UnusedDetector().detectResolved(sources, config);
  }

  test('homonym methods on different classes are independent nodes', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
import 'src/a.dart';
import 'src/b.dart';

void main() {
  A().work();
}

void useB(B b) => b;
''');
    await File('${dir.path}/lib/src/a.dart').writeAsString('''
class A {
  void work() {}
}
''');
    await File('${dir.path}/lib/src/b.dart').writeAsString('''
class B {
  void work() {}
}
''');
    final unused = await detectIn(const UnusedConfig(excludeExported: false));
    final byKind = <UnusedKind, List<String>>{};
    for (final u in unused) {
      byKind.putIfAbsent(u.kind, () => []).add(u.name);
    }
    // A.work() is reachable via main()'s call. B.work() is NOT reachable
    // because the simple-name match would have kept it alive in v0.1's
    // detector — element resolution distinguishes them.
    expect(byKind[UnusedKind.method], contains('work'));
    final workEntries = unused.where((u) => u.name == 'work').toList();
    expect(workEntries, hasLength(1));
    expect(workEntries.single.location.path, endsWith('b.dart'));
  });

  test('@override auto-roots an instance method even when nothing else '
      'in source calls it', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
import 'src/a.dart';

void main() {
  print(A());
}
''');
    await File('${dir.path}/lib/src/a.dart').writeAsString('''
class A {
  @override
  String toString() => 'A';
}
''');
    final unused = await detectIn(const UnusedConfig(excludeExported: false));
    final names = unused.map((u) => u.name).toList();
    expect(names, isNot(contains('toString')));
  });

  test('Object dunder names auto-root even without @override', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
import 'src/a.dart';

void main() {
  A();
}
''');
    await File('${dir.path}/lib/src/a.dart').writeAsString('''
class A {
  String toString() => 'A';
  int get hashCode => 0;
  bool operator ==(Object other) => other is A;
}
''');
    final unused = await detectIn(const UnusedConfig(excludeExported: false));
    final names = unused.map((u) => u.name).toList();
    expect(names, isNot(contains('toString')));
    expect(names, isNot(contains('hashCode')));
    expect(names, isNot(contains('==')));
  });

  test('unused method is reported at member granularity even when its '
      'class is reachable', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
import 'src/a.dart';

void main() {
  A().used();
}
''');
    await File('${dir.path}/lib/src/a.dart').writeAsString('''
class A {
  void used() {}
  void unusedMember() {}
}
''');
    final unused = await detectIn(const UnusedConfig(excludeExported: false));
    final methodNames = unused
        .where((u) => u.kind == UnusedKind.method)
        .map((u) => u.name)
        .toList();
    expect(methodNames, contains('unusedMember'));
    expect(methodNames, isNot(contains('used')));
  });

  test('field reference resolves through the synthetic getter and '
      'collapses to the field element', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
import 'src/a.dart';

void main() {
  print(A().value);
  A().unusedField = 1;
}
''');
    await File('${dir.path}/lib/src/a.dart').writeAsString('''
class A {
  int value = 1;
  int unusedField = 2;
}
''');
    final unused = await detectIn(const UnusedConfig(excludeExported: false));
    final fields = unused
        .where((u) => u.kind == UnusedKind.field)
        .map((u) => u.name)
        .toList();
    // Both fields are *referenced* in main(), so neither is unused in
    // this fixture — the test confirms synthetic-accessor collapse
    // works on read AND write.
    expect(fields, isNot(contains('value')));
    expect(fields, isNot(contains('unusedField')));
  });

  test(
    'SDK / dart:core symbol does not keep a project-local homonym alive',
    () async {
      await File('${dir.path}/lib/foo.dart').writeAsString('''
void main() {
  print('hello');
}
''');
      await File('${dir.path}/lib/src/a.dart').writeAsString('''
class Iterable {}
''');
      final unused = await detectIn(const UnusedConfig(excludeExported: false));
      // The simple-name graph would have kept the project's `Iterable`
      // alive because `print` indirectly references the SDK `Iterable`
      // somewhere. Element resolution checks identity, not name.
      final names = unused.map((u) => u.name).toList();
      expect(names, contains('Iterable'));
    },
  );

  test('--filter narrows the report to the requested kinds', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
import 'src/a.dart';

void main() {
  A();
}

void unusedTopLevel() {}
''');
    await File('${dir.path}/lib/src/a.dart').writeAsString('''
class A {
  void unusedMember() {}
}
class UnusedClass {}
''');
    final unused = await detectIn(
      const UnusedConfig(excludeExported: false, filter: ['method']),
    );
    final kinds = unused.map((u) => u.kind).toSet();
    expect(kinds, equals({UnusedKind.method}));
    final names = unused.map((u) => u.name).toList();
    expect(names, contains('unusedMember'));
    expect(names, isNot(contains('unusedTopLevel')));
    expect(names, isNot(contains('UnusedClass')));
  });

  test('parseUnusedFilter throws FormatException for unknown kind', () {
    expect(() => parseUnusedFilter(['bogus']), throwsA(isA<FormatException>()));
  });

  test('export show: re-exported class and its public members are roots '
      'under excludeExported', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
export 'src/a.dart' show Widget;
''');
    await File('${dir.path}/lib/src/a.dart').writeAsString('''
class Widget {
  void publicMethod() {}
  void _private() {}
}
class Hidden {}
''');
    final unused = await detectIn(const UnusedConfig());
    final names = unused.map((u) => u.name).toList();
    // `Widget` is re-exported, so Widget + Widget.publicMethod survive.
    expect(names, isNot(contains('Widget')));
    expect(names, isNot(contains('publicMethod')));
    // `Hidden` is not in the show list, so it remains unused.
    expect(names, contains('Hidden'));
  });

  test(
    'private (underscore-prefixed) declarations are never reported',
    () async {
      await File('${dir.path}/lib/foo.dart').writeAsString('''
class A {
  void _privateMember() {}
}
class _PrivateClass {}
void _privateFn() {}
void main() {
  A();
}
''');
      final unused = await detectIn(const UnusedConfig(excludeExported: false));
      final names = unused.map((u) => u.name).toList();
      expect(names, isNot(contains('_privateMember')));
      expect(names, isNot(contains('_PrivateClass')));
      expect(names, isNot(contains('_privateFn')));
    },
  );

  test(
    '@pragma("vm:entry-point") roots a method even without @override',
    () async {
      await File('${dir.path}/lib/foo.dart').writeAsString('''
import 'src/a.dart';
void main() {
  A();
}
''');
      await File('${dir.path}/lib/src/a.dart').writeAsString('''
class A {
  @pragma('vm:entry-point')
  void exposed() {}
}
''');
      final unused = await detectIn(const UnusedConfig(excludeExported: false));
      final names = unused.map((u) => u.name).toList();
      expect(names, isNot(contains('exposed')));
    },
  );

  test('enum value granularity: unused enum constants are reported '
      'separately from the enum type', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
import 'src/a.dart';
void main() {
  E.used;
}
''');
    await File('${dir.path}/lib/src/a.dart').writeAsString('''
enum E { used, neverUsed }
''');
    final unused = await detectIn(const UnusedConfig(excludeExported: false));
    final byKind = {
      for (final k in UnusedKind.values)
        k: unused.where((u) => u.kind == k).map((u) => u.name).toList(),
    };
    expect(byKind[UnusedKind.klass], isNot(contains('E')));
    expect(byKind[UnusedKind.enumValue], contains('neverUsed'));
    expect(byKind[UnusedKind.enumValue], isNot(contains('used')));
  });

  test('typedef and top-level field detection still works '
      'in resolved mode', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
typedef Used = int;
typedef Unused = String;
const usedField = 1;
const unusedField = 2;
void main() {
  Used x = usedField;
  print(x);
}
''');
    final unused = await detectIn(const UnusedConfig(excludeExported: false));
    final names = unused.map((u) => u.name).toList();
    expect(names, contains('Unused'));
    expect(names, contains('unusedField'));
    expect(names, isNot(contains('Used')));
    expect(names, isNot(contains('usedField')));
  });

  test('mixin and extension-type declarations are tracked at member '
      'granularity', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
mixin UsedMixin {
  void usedMethod() {}
  void unusedMixinMember() {}
}
mixin UnusedMixin {}
extension type Wrapped(int x) {
  int doubled() => x * 2;
  int unusedTypeMember() => x;
}
void main() {
  final c = _C();
  c.usedMethod();
  Wrapped(3).doubled();
}
class _C with UsedMixin {}
''');
    final unused = await detectIn(const UnusedConfig(excludeExported: false));
    final names = unused.map((u) => u.name).toList();
    expect(names, contains('UnusedMixin'));
    expect(names, contains('unusedMixinMember'));
    expect(names, contains('unusedTypeMember'));
    expect(names, isNot(contains('UsedMixin')));
    expect(names, isNot(contains('Wrapped')));
    expect(names, isNot(contains('doubled')));
    expect(names, isNot(contains('usedMethod')));
  });

  test('old-style typedef syntax is collected in resolved mode', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
typedef int LegacyComparator(int a, int b);
void main() {
  LegacyComparator? cb;
  print(cb);
}
typedef int UnusedLegacyComparator(int a, int b);
''');
    final unused = await detectIn(const UnusedConfig(excludeExported: false));
    final names = unused.map((u) => u.name).toList();
    expect(names, contains('UnusedLegacyComparator'));
    expect(names, isNot(contains('LegacyComparator')));
  });

  test('named extension is registered as `extension` kind and its '
      'members are tracked individually', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
extension UsedExt on int {
  int twice() => this * 2;
  int unusedExtMethod() => this;
}
extension UnusedExt on String {
  int len() => length;
}
void main() {
  3.twice();
}
''');
    final unused = await detectIn(const UnusedConfig(excludeExported: false));
    final byKind = <UnusedKind, List<String>>{};
    for (final u in unused) {
      byKind.putIfAbsent(u.kind, () => []).add(u.name);
    }
    expect(byKind[UnusedKind.extension], contains('UnusedExt'));
    expect(byKind[UnusedKind.extension] ?? [], isNot(contains('UsedExt')));
    expect(byKind[UnusedKind.method], contains('unusedExtMethod'));
    expect(byKind[UnusedKind.method] ?? [], isNot(contains('twice')));
  });

  test('enum members (not just constants) are tracked individually', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
import 'src/a.dart';
void main() {
  E.first.usedHelper();
}
''');
    await File('${dir.path}/lib/src/a.dart').writeAsString('''
enum E {
  first,
  second;
  void usedHelper() {}
  void unusedEnumMethod() {}
}
''');
    final unused = await detectIn(const UnusedConfig(excludeExported: false));
    final names = unused.map((u) => u.name).toList();
    expect(names, contains('unusedEnumMethod'));
    expect(names, contains('second'));
    expect(names, isNot(contains('usedHelper')));
    expect(names, isNot(contains('first')));
  });

  test('unnamed extension does not register itself but its members are '
      'still tracked', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
extension on int {
  int triple() => this * 3;
  int unusedExtMember() => this;
}
void main() {
  3.triple();
}
''');
    final unused = await detectIn(const UnusedConfig(excludeExported: false));
    final names = unused.map((u) => u.name).toList();
    expect(names, contains('unusedExtMember'));
    expect(names, isNot(contains('triple')));
  });

  test('@reflectiveTest class propagates keep-alive to its members', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
class _ReflectiveTest {
  const _ReflectiveTest();
}
const reflectiveTest = _ReflectiveTest();

@reflectiveTest
class SuiteUnderTest {
  void test_first() {}
  void test_second() {}
}
void main() {
  SuiteUnderTest();
}
''');
    final unused = await detectIn(const UnusedConfig(excludeExported: false));
    final names = unused.map((u) => u.name).toList();
    expect(names, isNot(contains('test_first')));
    expect(names, isNot(contains('test_second')));
  });

  test('export-namespace member walk roots getters / setters in addition '
      'to methods and fields', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
export 'src/a.dart' show Widget;
''');
    await File('${dir.path}/lib/src/a.dart').writeAsString('''
class Widget {
  int _x = 1;
  int get value => _x;
  set value(int v) => _x = v;
  void method() {}
  int field = 0;
}
''');
    final unused = await detectIn(const UnusedConfig());
    final names = unused.map((u) => u.name).toList();
    // Every public member of the re-exported class must remain alive.
    expect(names, isNot(contains('value')));
    expect(names, isNot(contains('method')));
    expect(names, isNot(contains('field')));
  });

  test('postfix x++ and prefix ++x writeback edges keep field alive', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
import 'src/a.dart';
void main() {
  final c = Counter();
  c.x++;
  ++c.y;
}
''');
    await File('${dir.path}/lib/src/a.dart').writeAsString('''
class Counter {
  int x = 0;
  int y = 0;
  int z = 0;
}
''');
    final unused = await detectIn(const UnusedConfig(excludeExported: false));
    final names = unused.map((u) => u.name).toList();
    expect(names, isNot(contains('x')));
    expect(names, isNot(contains('y')));
    expect(names, contains('z'));
  });

  test('ConstructorReference (Foo.new) keeps the class alive', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
import 'src/a.dart';

void main() {
  final make = A.new;
  make();
}
''');
    await File('${dir.path}/lib/src/a.dart').writeAsString('''
class A {
  A();
}
class UnusedClass {}
''');
    final unused = await detectIn(const UnusedConfig(excludeExported: false));
    final names = unused.map((u) => u.name).toList();
    expect(names, isNot(contains('A')));
    expect(names, contains('UnusedClass'));
  });

  test(
    'field metadata annotations contribute outgoing edges, so '
    '`@annot final Marker x;` keeps both the typedef and the '
    'annotation class alive',
    () async {
      await File('${dir.path}/lib/foo.dart').writeAsString('''
import 'src/a.dart';
void main() {
  print(Holder().label);
}
''');
      await File('${dir.path}/lib/src/a.dart').writeAsString('''
typedef Marker = String;
class Annot {
  const Annot();
}
const annot = Annot();

class Holder {
  @annot
  final Marker label = 'x';
}
''');
      final unused = await detectIn(
        const UnusedConfig(excludeExported: false),
      );
      final names = unused.map((u) => u.name).toList();
      // The shared type `Marker` is on the parent FieldDeclaration; the
      // annotation `@annot` (and its element `Annot`) live in
      // metadata. Both must reach through the field's outgoing set so
      // they don't get reported as unused.
      expect(names, isNot(contains('Marker')));
      expect(names, isNot(contains('Annot')));
      expect(names, isNot(contains('annot')));
    },
  );

  test(
    'explicit constructor declarations are walked but not separately '
    'tracked — calls inside the constructor body keep helpers alive',
    () async {
      await File('${dir.path}/lib/foo.dart').writeAsString('''
import 'src/a.dart';
void main() {
  Container(1);
}
''');
      await File('${dir.path}/lib/src/a.dart').writeAsString('''
class Container {
  Container(int seed) {
    helperFromCtor(seed);
  }
  void unusedMember() {}
}
void helperFromCtor(int x) {}
void unusedHelper() {}
''');
      final unused = await detectIn(const UnusedConfig(excludeExported: false));
      final names = unused.map((u) => u.name).toList();
      // `helperFromCtor` is only called from inside Container's constructor
      // body — it must stay alive when the class is reachable.
      expect(names, isNot(contains('helperFromCtor')));
      expect(names, contains('unusedHelper'));
      // Non-constructor members keep per-member granularity:
      expect(names, contains('unusedMember'));
    },
  );
}
