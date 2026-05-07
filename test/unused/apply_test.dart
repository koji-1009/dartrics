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

  test('emits unsupportedKind for method / field / enumValue', () {
    final f = File('${dir.path}/lib.dart');
    f.writeAsStringSync('''
class C {
  void m() {}
}
''');
    final results = applyDeletions([
      UnusedDeclaration(
        kind: UnusedKind.method,
        name: 'm',
        location: SourceLocation(path: f.path, line: 2, column: 1),
      ),
    ], includeTests: false);
    expect(results.single.outcome, ApplyOutcome.unsupportedKind);
    // File is untouched.
    expect(f.readAsStringSync(), contains('void m()'));
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

  group('buildApplySummary', () {
    UnusedDeclaration mk(UnusedKind kind, String name) => UnusedDeclaration(
      kind: kind,
      name: name,
      location: const SourceLocation(path: 'lib/x.dart', line: 1, column: 1),
    );

    test('summary names unsupported addendum when relevant', () {
      final body = buildApplySummary([
        ApplyResult(
          target: mk(UnusedKind.field, 'F'),
          outcome: ApplyOutcome.unsupportedKind,
        ),
      ]);
      expect(body, contains('deleted 0'));
      expect(body, contains('unsupported 1'));
      expect(body, contains('unsupported kinds (method / field / enumValue)'));
    });

    test('summary names notFound addendum when relevant', () {
      final body = buildApplySummary([
        ApplyResult(
          target: mk(UnusedKind.function, 'f'),
          outcome: ApplyOutcome.notFound,
        ),
      ]);
      expect(body, contains('not found 1'));
      expect(body, contains('"not found" entries indicate the source changed'));
    });

    test('summary omits both addenda when totals are zero', () {
      final body = buildApplySummary([
        ApplyResult(
          target: mk(UnusedKind.function, 'f'),
          outcome: ApplyOutcome.deleted,
        ),
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
}
