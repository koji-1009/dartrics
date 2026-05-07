import 'dart:io';

import 'package:dartrics/src/cli/unused_command.dart' show buildApplySummary;
import 'package:dartrics/src/models/source_location.dart';
import 'package:dartrics/src/models/unused_declaration.dart';
import 'package:dartrics/src/unused/apply.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('apply_test_');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('deletes a top-level function', () {
    final f = File('${dir.path}/lib.dart');
    f.writeAsStringSync('''
void main() {
  used();
}

void used() {}

void unused() {
  print('bye');
}
''');
    final results = applyDeletions([
      UnusedDeclaration(
        kind: UnusedKind.function,
        name: 'unused',
        location: SourceLocation(path: f.path, line: 7, column: 1),
      ),
    ], includeTests: false);
    expect(results.single.outcome, ApplyOutcome.deleted);
    final after = f.readAsStringSync();
    expect(after.contains('void unused()'), isFalse);
    expect(after.contains('void main()'), isTrue);
    expect(after.contains('void used()'), isTrue);
  });

  test('preserves doc comments + annotations on the deleted declaration', () {
    final f = File('${dir.path}/lib.dart');
    f.writeAsStringSync('''
void main() => stillHere();

/// Doc on the unused thing.
@deprecated
void gone() {}

void stillHere() {}
''');
    final results = applyDeletions([
      UnusedDeclaration(
        kind: UnusedKind.function,
        name: 'gone',
        location: SourceLocation(path: f.path, line: 5, column: 1),
      ),
    ], includeTests: false);
    expect(results.single.outcome, ApplyOutcome.deleted);
    final after = f.readAsStringSync();
    expect(after.contains('Doc on the unused'), isFalse);
    expect(after.contains('@deprecated'), isFalse);
    expect(after.contains('void gone()'), isFalse);
    expect(after.contains('void stillHere()'), isTrue);
  });

  test('descending-offset deletion does not corrupt earlier ranges', () {
    final f = File('${dir.path}/lib.dart');
    f.writeAsStringSync('''
class A {}

class B {}

class C {}

class Used {
  void use(A a, B b, C c) {}
}
''');
    final results = applyDeletions([
      UnusedDeclaration(
        kind: UnusedKind.klass,
        name: 'A',
        location: SourceLocation(path: f.path, line: 1, column: 1),
      ),
      UnusedDeclaration(
        kind: UnusedKind.klass,
        name: 'C',
        location: SourceLocation(path: f.path, line: 5, column: 1),
      ),
    ], includeTests: false);
    expect(results.map((r) => r.outcome), [
      ApplyOutcome.deleted,
      ApplyOutcome.deleted,
    ]);
    final after = f.readAsStringSync();
    expect(after.contains('class A {}'), isFalse);
    expect(after.contains('class C {}'), isFalse);
    expect(after.contains('class B {}'), isTrue);
    expect(after.contains('class Used'), isTrue);
  });

  test('skips test/ files when includeTests is false', () {
    Directory('${dir.path}/test').createSync();
    final tf = File('${dir.path}/test/foo_test.dart');
    tf.writeAsStringSync('void unused() {}\nvoid main() {}\n');
    final results = applyDeletions([
      UnusedDeclaration(
        kind: UnusedKind.function,
        name: 'unused',
        location: SourceLocation(path: tf.path, line: 1, column: 1),
      ),
    ], includeTests: false);
    expect(results.single.outcome, ApplyOutcome.skippedTest);
    expect(tf.readAsStringSync(), contains('void unused()'));
  });

  test('includes test/ files when includeTests is true', () {
    Directory('${dir.path}/test').createSync();
    final tf = File('${dir.path}/test/foo_test.dart');
    tf.writeAsStringSync('void unused() {}\nvoid main() {}\n');
    final results = applyDeletions([
      UnusedDeclaration(
        kind: UnusedKind.function,
        name: 'unused',
        location: SourceLocation(path: tf.path, line: 1, column: 1),
      ),
    ], includeTests: true);
    expect(results.single.outcome, ApplyOutcome.deleted);
    expect(tf.readAsStringSync(), isNot(contains('void unused()')));
  });

  test('deletes an instance method by name + line', () {
    final f = File('${dir.path}/lib.dart');
    f.writeAsStringSync('''
class C {
  void used() {}
  void gone() {
    print('removed');
  }
}
''');
    final results = applyDeletions([
      UnusedDeclaration(
        kind: UnusedKind.method,
        name: 'gone',
        location: SourceLocation(path: f.path, line: 3, column: 3),
      ),
    ], includeTests: false);
    expect(results.single.outcome, ApplyOutcome.deleted);
    final after = f.readAsStringSync();
    expect(after, contains('void used()'));
    expect(after, isNot(contains('void gone()')));
  });

  test('deletes a single-variable instance field', () {
    final f = File('${dir.path}/lib.dart');
    f.writeAsStringSync('''
class C {
  int kept = 1;
  int unused = 2;
}
''');
    final results = applyDeletions([
      UnusedDeclaration(
        kind: UnusedKind.field,
        name: 'unused',
        location: SourceLocation(path: f.path, line: 3, column: 7),
      ),
    ], includeTests: false);
    expect(results.single.outcome, ApplyOutcome.deleted);
    final after = f.readAsStringSync();
    expect(after, contains('int kept = 1;'));
    expect(after, isNot(contains('int unused')));
  });

  test('deletes one variable from a multi-variable declaration: '
      'middle of `int x, y, z;` becomes `int x, z;`', () {
    final f = File('${dir.path}/lib.dart');
    f.writeAsStringSync('''
class C {
  int x = 1, y = 2, z = 3;
  int sum() => x + z;
}
''');
    final results = applyDeletions([
      UnusedDeclaration(
        kind: UnusedKind.field,
        name: 'y',
        location: SourceLocation(path: f.path, line: 2, column: 14),
      ),
    ], includeTests: false);
    expect(results.single.outcome, ApplyOutcome.deleted);
    final after = f.readAsStringSync();
    expect(after, contains('int x = 1, z = 3;'));
    expect(after, isNot(contains('y = 2')));
  });

  test('deletes the last variable from a multi-variable declaration: '
      '`int x, y, z;` becomes `int x, y;`', () {
    final f = File('${dir.path}/lib.dart');
    f.writeAsStringSync('''
class C {
  int x = 1, y = 2, z = 3;
  int sum() => x + y;
}
''');
    final results = applyDeletions([
      UnusedDeclaration(
        kind: UnusedKind.field,
        name: 'z',
        location: SourceLocation(path: f.path, line: 2, column: 21),
      ),
    ], includeTests: false);
    expect(results.single.outcome, ApplyOutcome.deleted);
    final after = f.readAsStringSync();
    expect(after, contains('int x = 1, y = 2;'));
    expect(after, isNot(contains('z = 3')));
  });

  test('deletes a top-level variable in a single-variable declaration', () {
    final f = File('${dir.path}/lib.dart');
    f.writeAsStringSync('''
const kept = 1;
const unused = 2;
void main() => print(kept);
''');
    final results = applyDeletions([
      UnusedDeclaration(
        kind: UnusedKind.field,
        name: 'unused',
        location: SourceLocation(path: f.path, line: 2, column: 7),
      ),
    ], includeTests: false);
    expect(results.single.outcome, ApplyOutcome.deleted);
    final after = f.readAsStringSync();
    expect(after, contains('const kept = 1;'));
    expect(after, isNot(contains('const unused = 2;')));
  });

  test('deletes one enum constant from a multi-constant enum', () {
    final f = File('${dir.path}/lib.dart');
    f.writeAsStringSync('''
enum E {
  a,
  b,
  c,
}
''');
    final results = applyDeletions([
      UnusedDeclaration(
        kind: UnusedKind.enumValue,
        name: 'b',
        location: SourceLocation(path: f.path, line: 3, column: 3),
      ),
    ], includeTests: false);
    expect(results.single.outcome, ApplyOutcome.deleted);
    final after = f.readAsStringSync();
    expect(after, contains('a,'));
    expect(after, contains('c,'));
    expect(after, isNot(contains('b,')));
  });

  test(
    'refuses to delete the only constant in an enum (would leave invalid Dart)',
    () {
      final f = File('${dir.path}/lib.dart');
      f.writeAsStringSync('enum E { lonely }\n');
      final results = applyDeletions([
        UnusedDeclaration(
          kind: UnusedKind.enumValue,
          name: 'lonely',
          location: SourceLocation(path: f.path, line: 1, column: 10),
        ),
      ], includeTests: false);
      expect(results.single.outcome, ApplyOutcome.unsupportedKind);
      expect(f.readAsStringSync(), 'enum E { lonely }\n');
    },
  );

  test('deletes the last enum constant in a multi-constant enum', () {
    final f = File('${dir.path}/lib.dart');
    f.writeAsStringSync('''
enum E {
  a,
  b,
  c,
}
''');
    final results = applyDeletions([
      UnusedDeclaration(
        kind: UnusedKind.enumValue,
        name: 'c',
        location: SourceLocation(path: f.path, line: 4, column: 3),
      ),
    ], includeTests: false);
    expect(results.single.outcome, ApplyOutcome.deleted);
    final after = f.readAsStringSync();
    expect(after, contains('a,'));
    expect(after, contains('b,'));
    expect(after, isNot(contains('c,')));
  });

  test('deletes a top-level extension type', () {
    final f = File('${dir.path}/lib.dart');
    f.writeAsStringSync('''
extension type Wrapped(int x) {}
extension type Kept(int x) {}
void main() => print(Kept(1));
''');
    final results = applyDeletions([
      UnusedDeclaration(
        kind: UnusedKind.klass,
        name: 'Wrapped',
        location: SourceLocation(path: f.path, line: 1, column: 1),
      ),
    ], includeTests: false);
    expect(results.single.outcome, ApplyOutcome.deleted);
    final after = f.readAsStringSync();
    expect(after, isNot(contains('Wrapped')));
    expect(after, contains('Kept'));
  });

  test('walks instance methods on mixins, extensions, '
      'extension types, and enums', () {
    final f = File('${dir.path}/lib.dart');
    f.writeAsStringSync('''
mixin M { void mMethod() {} }
extension Ex on int { void exMethod() {} }
extension type T(int x) { void tMethod() {} }
enum E {
  a;
  void eMethod() {}
}
''');
    final results = applyDeletions([
      UnusedDeclaration(
        kind: UnusedKind.method,
        name: 'mMethod',
        location: SourceLocation(path: f.path, line: 1, column: 12),
      ),
      UnusedDeclaration(
        kind: UnusedKind.method,
        name: 'exMethod',
        location: SourceLocation(path: f.path, line: 2, column: 23),
      ),
      UnusedDeclaration(
        kind: UnusedKind.method,
        name: 'tMethod',
        location: SourceLocation(path: f.path, line: 3, column: 27),
      ),
      UnusedDeclaration(
        kind: UnusedKind.method,
        name: 'eMethod',
        location: SourceLocation(path: f.path, line: 6, column: 3),
      ),
    ], includeTests: false);
    expect(results.map((r) => r.outcome), everyElement(ApplyOutcome.deleted));
    final after = f.readAsStringSync();
    expect(after, isNot(contains('mMethod')));
    expect(after, isNot(contains('exMethod')));
    expect(after, isNot(contains('tMethod')));
    expect(after, isNot(contains('eMethod')));
  });

  test('merges nested ranges so deleting a class + its method '
      'in one pass does not crash on shifted offsets', () {
    final f = File('${dir.path}/lib.dart');
    f.writeAsStringSync('''
class Drop {
  void inner() {}
}
void main() {}
''');
    final results = applyDeletions([
      UnusedDeclaration(
        kind: UnusedKind.method,
        name: 'inner',
        location: SourceLocation(path: f.path, line: 2, column: 3),
      ),
      UnusedDeclaration(
        kind: UnusedKind.klass,
        name: 'Drop',
        location: SourceLocation(path: f.path, line: 1, column: 1),
      ),
    ], includeTests: false);
    expect(results.map((r) => r.outcome), everyElement(ApplyOutcome.deleted));
    final after = f.readAsStringSync();
    expect(after, isNot(contains('class Drop')));
    expect(after, isNot(contains('inner')));
    expect(after, contains('void main()'));
  });

  test('merges two non-nested ranges that happen to touch', () {
    // Two top-level functions back-to-back. Their _rangeFor extends
    // through trailing newlines so the second function's range starts
    // exactly where the first ends — _mergeRanges' "next.start <
    // current.end" guard hits the fall-through (no extension needed)
    // path.
    final f = File('${dir.path}/lib.dart');
    f.writeAsStringSync('void a() {}\nvoid b() {}\nvoid main() {}\n');
    final results = applyDeletions([
      UnusedDeclaration(
        kind: UnusedKind.function,
        name: 'a',
        location: SourceLocation(path: f.path, line: 1, column: 1),
      ),
      UnusedDeclaration(
        kind: UnusedKind.function,
        name: 'b',
        location: SourceLocation(path: f.path, line: 2, column: 1),
      ),
    ], includeTests: false);
    expect(results.map((r) => r.outcome), everyElement(ApplyOutcome.deleted));
    final after = f.readAsStringSync();
    expect(after, 'void main() {}\n');
  });

  test('reports notFound when name/line does not match any declaration', () {
    final f = File('${dir.path}/lib.dart');
    f.writeAsStringSync('void main() {}\n');
    final results = applyDeletions([
      UnusedDeclaration(
        kind: UnusedKind.function,
        name: 'whatever',
        location: SourceLocation(path: f.path, line: 99, column: 1),
      ),
    ], includeTests: false);
    expect(results.single.outcome, ApplyOutcome.notFound);
    expect(f.readAsStringSync(), 'void main() {}\n');
  });

  test('isGitTreeClean returns true when not in a git repo', () {
    expect(isGitTreeClean(dir.path), isTrue);
  });

  test('isGitTreeClean returns true on a clean git repo and false on a '
      'dirty one', () async {
    final repo = await Directory.systemTemp.createTemp('apply_clean_');
    addTearDown(() => repo.delete(recursive: true));
    final init = await Process.run('git', [
      'init',
      '-q',
      '-b',
      'main',
    ], workingDirectory: repo.path);
    expect(init.exitCode, 0);
    await Process.run('git', [
      'config',
      'commit.gpgsign',
      'false',
    ], workingDirectory: repo.path);
    // Empty, just-initialised repo has no changes — porcelain output
    // is empty so the clean-tree branch is exercised.
    expect(isGitTreeClean(repo.path), isTrue);
    // Adding an untracked file flips the result.
    File('${repo.path}/note.txt').writeAsStringSync('hi');
    expect(isGitTreeClean(repo.path), isFalse);
  });

  group('buildApplySummary', () {
    test('summary names unsupported addendum when relevant', () {
      final body = buildApplySummary([
        ApplyResult(outcome: ApplyOutcome.unsupportedKind),
      ]);
      expect(body, contains('deleted 0'));
      expect(body, contains('unsupported 1'));
      expect(body, contains('unsupported kinds (method / field / enumValue)'));
    });

    test('summary names notFound addendum when relevant', () {
      final body = buildApplySummary([
        ApplyResult(outcome: ApplyOutcome.notFound),
      ]);
      expect(body, contains('not found 1'));
      expect(body, contains('"not found" entries indicate the source changed'));
    });

    test('summary omits both addenda when totals are zero', () {
      final body = buildApplySummary([
        ApplyResult(outcome: ApplyOutcome.deleted),
      ]);
      expect(body, isNot(contains('unsupported kinds')));
      expect(body, isNot(contains('"not found"')));
    });
  });

  test('consumes trailing horizontal whitespace before the newline', () {
    // The closing `}` followed by spaces + newline — the range
    // computation walks past those spaces so the subsequent line
    // starts cleanly. Use   to make the trailing space visible
    // in source.
    final f = File('${dir.path}/lib.dart');
    f.writeAsStringSync('void keep() {}\nvoid drop() {}   \nint x = 0;\n');
    final results = applyDeletions([
      UnusedDeclaration(
        kind: UnusedKind.function,
        name: 'drop',
        location: SourceLocation(path: f.path, line: 2, column: 1),
      ),
    ], includeTests: false);
    expect(results.single.outcome, ApplyOutcome.deleted);
    final after = f.readAsStringSync();
    // No leftover blank line where `drop` used to live.
    expect(after, 'void keep() {}\nint x = 0;\n');
  });

  test('deletes a top-level typedef (generic alias form)', () {
    // `typedef Foo = ...;` parses as `GenericTypeAlias`, distinct from
    // the legacy `typedef int Cb(int);` form which parses as
    // `FunctionTypeAlias`. Both kinds are supported by --apply.
    final f = File('${dir.path}/lib.dart');
    f.writeAsStringSync(
      'void main() {}\n'
      '\n'
      'typedef Stale = int Function(int);\n'
      '\n'
      'int keep() => 0;\n',
    );
    final results = applyDeletions([
      UnusedDeclaration(
        kind: UnusedKind.typedef,
        name: 'Stale',
        location: SourceLocation(path: f.path, line: 3, column: 1),
      ),
    ], includeTests: false);
    expect(results.single.outcome, ApplyOutcome.deleted);
    final after = f.readAsStringSync();
    expect(after.contains('typedef Stale'), isFalse);
    expect(after.contains('int keep()'), isTrue);
  });

  test('deletes a top-level legacy typedef (function-type alias form)', () {
    final f = File('${dir.path}/lib.dart');
    f.writeAsStringSync(
      'void main() {}\n'
      '\n'
      'typedef int LegacyCb(int x);\n'
      '\n'
      'int keep() => 0;\n',
    );
    final results = applyDeletions([
      UnusedDeclaration(
        kind: UnusedKind.typedef,
        name: 'LegacyCb',
        location: SourceLocation(path: f.path, line: 3, column: 1),
      ),
    ], includeTests: false);
    expect(results.single.outcome, ApplyOutcome.deleted);
    final after = f.readAsStringSync();
    expect(after.contains('LegacyCb'), isFalse);
  });

  test('deletes a top-level extension (named form)', () {
    final f = File('${dir.path}/lib.dart');
    f.writeAsStringSync(
      'void main() {}\n'
      '\n'
      'extension StringX on String {\n'
      '  int get answer => 42;\n'
      '}\n'
      '\n'
      'int keep() => 0;\n',
    );
    final results = applyDeletions([
      UnusedDeclaration(
        kind: UnusedKind.extension,
        name: 'StringX',
        location: SourceLocation(path: f.path, line: 3, column: 1),
      ),
    ], includeTests: false);
    expect(results.single.outcome, ApplyOutcome.deleted);
    final after = f.readAsStringSync();
    expect(after.contains('StringX'), isFalse);
    expect(after.contains('int keep()'), isTrue);
  });
}
