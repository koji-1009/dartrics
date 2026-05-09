import 'package:analyzer/dart/ast/ast.dart';

/// Pure-AST helpers used by the metric engine and the analyzer plugin to
/// recognise idiomatic Flutter widgets.
///
/// dartrics measures the same control-flow signals on `Widget.build()`
/// as it does on any other method — `maximum-nesting-level` and
/// `method-length` apply, because deeply-nested control flow inside
/// `build()` is just as hard to read as it is anywhere else. The visual
/// depth from chained Widget literals does **not** affect those metrics
/// (`MaxNestingLevel` only counts `if` / `for` / `while` / `do` / `switch`
/// / `try` / closure bodies, not `InstanceCreationExpression`s), so a
/// healthy `Container > Padding > Row > Column > ...` tree produces a
/// nesting score of 0.
///
/// Widget literal nesting itself is the responsibility of a separate
/// `widget-tree-depth` lens (see `widget_tree_depth.dart`), which lets
/// users tune Widget-tree depth thresholds independently from
/// control-flow nesting.
///
/// What this helper still does: skip `number-of-parameters` on widget
/// **constructors**. `key:` plus a long list of callback / typed-init
/// parameters is the cultural norm for `StatelessWidget` /
/// `StatefulWidget` constructors, and it does not carry the same call-
/// site readability penalty that arbitrary boolean / positional
/// parameters do. Other methods on the same widget — including helper
/// builders, lifecycle hooks, and `_buildSomething` private helpers —
/// are measured normally.
abstract final class FlutterAware {
  /// Superclass names that mark a class as a widget for skip purposes.
  /// Covers stock Flutter, Riverpod's `ConsumerWidget`/`ConsumerStatefulWidget`,
  /// and `flutter_hooks`'s `HookWidget` / `HookConsumerWidget`.
  static const Set<String> widgetSuperclasses = {
    'StatelessWidget',
    'StatefulWidget',
    'State',
    'ConsumerWidget',
    'ConsumerStatefulWidget',
    'HookWidget',
    'HookConsumerWidget',
  };

  /// Metrics skipped when the declaration is a widget's constructor.
  /// `key:` plus a long list of callbacks is the idiom for stateless /
  /// stateful widget constructors and shouldn't be flagged as
  /// boolean-trap-style call-site noise.
  static const Set<String> constructorSkips = {'number-of-parameters'};

  /// Returns the set of metric ids that should be skipped for [decl] in
  /// Flutter-aware mode. Empty for non-widget code, for widget
  /// `build()` (which is measured normally), and for declarations
  /// inside a widget that aren't the constructor.
  static Set<String> skipsFor(Declaration decl) {
    if (decl is ConstructorDeclaration) {
      if (_enclosingClassIsWidget(decl)) return constructorSkips;
    }
    return const {};
  }

  /// Returns true when [cls]'s `extends` clause names one of the known
  /// widget superclasses. Generic-arg widgets (`State<MyWidget>`) are
  /// matched on the bare type name.
  static bool isWidgetClass(ClassDeclaration cls) {
    final extendsClause = cls.extendsClause;
    if (extendsClause == null) return false;
    final superclass = extendsClause.superclass.name.lexeme;
    return widgetSuperclasses.contains(superclass);
  }

  static bool _enclosingClassIsWidget(AstNode node) {
    AstNode? parent = node.parent;
    while (parent != null) {
      if (parent is ClassDeclaration) return isWidgetClass(parent);
      parent = parent.parent;
    }
    return false;
  }
}
