import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dartrics/src/dismiss/comment_parser.dart';
import 'package:dartrics/src/dismiss/dismissal.dart';
import 'package:test/test.dart';

void main() {
  List<Dismissal> scan(String source, {String path = 'lib/foo.dart'}) {
    final result = parseString(content: source);
    return scanCommentDismissals(
      path: path,
      unit: result.unit,
      lineInfo: result.lineInfo,
    );
  }

  test('captures a single comment dismissal above a function', () {
    final out = scan('''
// dartrics:dismiss cyclomatic-complexity reason="state machine — splitting hides intent"
int parse(int x) => x;
''');
    expect(out, hasLength(1));
    expect(out.single.metricId, 'cyclomatic-complexity');
    expect(out.single.scope, 'parse');
    expect(out.single.source, DismissalSource.comment);
    expect(out.single.reason, 'state machine — splitting hides intent');
    expect(out.single.file, 'lib/foo.dart');
  });

  test('captures stacked dismissals on the same declaration', () {
    final out = scan('''
// dartrics:dismiss cyclomatic-complexity reason="state machine: splitting hides intent"
// dartrics:dismiss method-length reason="state machine: splitting hides intent"
int parse(int x) => x;
''');
    expect(out, hasLength(2));
    expect(out.map((d) => d.metricId).toSet(), {
      'cyclomatic-complexity',
      'method-length',
    });
  });

  test('blank line between comment and declaration drops the dismiss', () {
    final out = scan('''
// dartrics:dismiss cyclomatic-complexity reason="this should not apply"

int parse(int x) => x;
''');
    expect(out, isEmpty);
  });

  test('blank line splits the stack, only the lower run survives', () {
    final out = scan('''
// dartrics:dismiss method-length reason="this is too far from the function"

// dartrics:dismiss cyclomatic-complexity reason="this is adjacent so it sticks"
int parse(int x) => x;
''');
    expect(out, hasLength(1));
    expect(out.single.metricId, 'cyclomatic-complexity');
  });

  test('non-matching comments are silently ignored', () {
    final out = scan('''
// dartrics:dismiss cyclomatic-complexity reason=missing_quotes
// regular comment
int parse(int x) => x;
''');
    expect(out, isEmpty);
  });

  test('matches scope name for class methods', () {
    final out = scan('''
class Foo {
  // dartrics:dismiss cyclomatic-complexity reason="class state machine adjacent"
  int bar(int x) => x;
}
''');
    expect(out, hasLength(1));
    expect(out.single.scope, 'Foo.bar');
  });

  test('matches scope for class declarations', () {
    final out = scan('''
// dartrics:dismiss number-of-methods reason="god-object scaffolding intentional"
class Wide {
  void a() {}
  void b() {}
}
''');
    expect(out, hasLength(1));
    expect(out.single.scope, 'Wide');
    expect(out.single.metricId, 'number-of-methods');
  });

  test('matches scope for default constructor', () {
    final out = scan('''
class Foo {
  // dartrics:dismiss cyclomatic-complexity reason="ctor branches mirror types"
  Foo(int x) {
    if (x < 0) {} else if (x == 0) {} else {}
  }
}
''');
    expect(out, hasLength(1));
    expect(out.single.scope, 'Foo');
  });

  test('matches scope for named constructor', () {
    final out = scan('''
class Foo {
  // dartrics:dismiss cyclomatic-complexity reason="named ctor handles all variants"
  Foo.named(int x) {
    if (x < 0) {} else if (x == 0) {} else {}
  }
}
''');
    expect(out, hasLength(1));
    expect(out.single.scope, 'Foo.named');
  });

  test('walks into mixin / extension / enum members', () {
    final out = scan('''
mixin M {
  // dartrics:dismiss method-length reason="mixin keeps things together"
  int m(int x) => x;
}
extension on int {
  // dartrics:dismiss method-length reason="extension intentionally fat"
  int doubled() => this * 2;
}
enum Color {
  red,
  green;
  // dartrics:dismiss method-length reason="enum-attached helper kept here"
  String describe() => name;
}
''');
    expect(out.map((d) => d.scope).toSet(), {
      'M.m',
      '<extension>.doubled',
      'Color.describe',
    });
  });
}
