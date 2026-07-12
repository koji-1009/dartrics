import 'package:dartrics/src/metrics/function/cyclomatic_complexity.dart';
import 'package:dartrics/src/metrics/function/number_of_parameters.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('closure scope naming', () {
    test('sibling closures number in source order', () {
      const source = '''
void f(List<int> xs) {
  xs.forEach((a) => print(a));
  xs.where((b) => b > 0);
}
''';
      expect(closureInputFor(source).scopeName, 'f.closure#1');
      expect(closureInputFor(source, index: 1).scopeName, 'f.closure#2');
    });

    test('nested closures number flat within the anchor', () {
      const source = '''
void f(List<int> xs) {
  xs.forEach((a) {
    xs.map((b) => b);
  });
  xs.where((c) => c > 0);
}
''';
      expect(closureInputFor(source, index: 1).scopeName, 'f.closure#2');
      expect(closureInputFor(source, index: 2).scopeName, 'f.closure#3');
    });

    test('closures inside a local function anchor to the local function', () {
      const source = '''
void f(List<int> xs) {
  void g() {
    xs.forEach((a) => print(a));
  }
  xs.where((b) => b > 0);
}
''';
      expect(closureInputFor(source).scopeName, 'g.closure#1');
      // g's closure doesn't consume an ordinal in f's numbering space.
      expect(closureInputFor(source, index: 1).scopeName, 'f.closure#1');
    });

    test('method and constructor closures carry the class-qualified name', () {
      const source = '''
class A {
  final int Function() cb;
  A() : cb = (() => 1);
  A.named() : cb = (() => 2);
  void m(List<int> xs) {
    xs.forEach((a) => print(a));
  }
}
''';
      expect(closureInputFor(source).scopeName, 'A.closure#1');
      expect(closureInputFor(source, index: 1).scopeName, 'A.named.closure#1');
      expect(closureInputFor(source, index: 2).scopeName, 'A.m.closure#1');
    });

    test(
      'field and top-level variable initializers anchor to the variable',
      () {
        const source = '''
final handler = (int x) => x + 1;

class A {
  final onTap = () {};
}
''';
        expect(closureInputFor(source).scopeName, 'handler.closure#1');
        expect(
          closureInputFor(source, index: 1).scopeName,
          'A.onTap.closure#1',
        );
      },
    );

    test('local variable initializers anchor to the enclosing callable', () {
      const source = '''
void f() {
  final check = (int x) => x > 0;
  check(1);
}
''';
      expect(closureInputFor(source).scopeName, 'f.closure#1');
    });
  });

  group('metrics computed on closure records', () {
    test('cyclomatic complexity measures the closure body alone', () {
      const cc = CyclomaticComplexity();
      const source = '''
void f(List<int> xs) {
  xs.forEach((a) {
    if (a > 0 && a < 10) print(a);
    xs.map((b) => b);
  });
}
''';
      // Outer closure: 1 + if + `&&`; its nested closure stays apart.
      expect(cc.compute(closureInputFor(source)), 3);
      expect(cc.compute(closureInputFor(source, index: 1)), 1);
    });

    test('number of parameters reads the closure parameter list', () {
      const nop = NumberOfParameters();
      const source = '''
void f(void Function(int, int, int) cb) {
  f((a, b, c) {});
}
''';
      expect(nop.compute(closureInputFor(source)), 3);
    });
  });
}
