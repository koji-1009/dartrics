import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:dartrics/src/metrics/flutter_aware.dart';
import 'package:test/test.dart';

void main() {
  group('FlutterAware', () {
    test('detects every well-known widget superclass', () {
      const supers = [
        'StatelessWidget',
        'StatefulWidget',
        'State',
        'ConsumerWidget',
        'ConsumerStatefulWidget',
        'HookWidget',
        'HookConsumerWidget',
      ];
      for (final s in supers) {
        final cls = _firstClass('class A extends $s {}');
        expect(FlutterAware.isWidgetClass(cls), isTrue, reason: s);
      }
    });

    test('non-widget classes are not flagged', () {
      expect(FlutterAware.isWidgetClass(_firstClass('class A {}')), isFalse);
      expect(
        FlutterAware.isWidgetClass(_firstClass('class A extends Object {}')),
        isFalse,
      );
    });

    test('build method on a widget is measured normally', () {
      // Contract: build() is measured for every default metric. Healthy
      // declarative Widget trees produce zero control-flow signal, so
      // no special-casing is needed.
      final cls = _firstClass('''
class W extends StatelessWidget {
  Widget build(BuildContext context) => Container();
}
''');
      final method = cls.body.members.whereType<MethodDeclaration>().single;
      expect(FlutterAware.skipsFor(method), isEmpty);
    });

    test('non-build method on a widget is not skipped', () {
      final cls = _firstClass('''
class W extends StatelessWidget {
  Widget _helper() => Container();
}
''');
      final method = cls.body.members.whereType<MethodDeclaration>().single;
      expect(FlutterAware.skipsFor(method), isEmpty);
    });

    test('non-widget class methods are not skipped', () {
      final cls = _firstClass('''
class Builder {
  void build() {}
}
''');
      final method = cls.body.members.whereType<MethodDeclaration>().single;
      expect(FlutterAware.skipsFor(method), isEmpty);
    });

    test('widget constructor skips number-of-parameters', () {
      final cls = _firstClass('''
class W extends StatelessWidget {
  W(this.a, this.b);
  final int a; final int b;
}
''');
      final ctor = cls.body.members.whereType<ConstructorDeclaration>().single;
      expect(FlutterAware.skipsFor(ctor), {'number-of-parameters'});
    });

    test('top-level function declarations are not skipped', () {
      final unit = parseString(content: 'void f() {}').unit;
      final fn = unit.declarations.whereType<FunctionDeclaration>().single;
      expect(FlutterAware.skipsFor(fn), isEmpty);
    });
  });
}

ClassDeclaration _firstClass(String source) {
  final unit = parseString(content: source).unit;
  return unit.declarations.whereType<ClassDeclaration>().first;
}
