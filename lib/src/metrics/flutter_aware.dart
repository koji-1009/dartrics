import 'package:analyzer/dart/ast/ast.dart';

/// Pure-AST helpers used by both the CLI metric engine and the analyzer
/// plugin to relax a small set of metrics on idiomatic Flutter widgets.
///
/// We deliberately stay at the AST layer (no element resolution) so the
/// plugin's per-file visitor stays cheap. The trade-off is that we
/// recognise widgets only by the unqualified superclass name.
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

  /// Metrics skipped when the declaration is a widget's `build` method.
  static const Set<String> buildSkips = {
    'maximum-nesting-level',
    'method-length',
  };

  /// Metrics skipped when the declaration is a widget's constructor.
  static const Set<String> constructorSkips = {'number-of-parameters'};

  /// Returns the set of metric ids that should be skipped for [decl] in
  /// Flutter-aware mode. Empty for non-widget code or for declarations
  /// inside a widget that aren't `build()`/the constructor.
  static Set<String> skipsFor(Declaration decl) {
    if (decl is MethodDeclaration && decl.name.lexeme == 'build') {
      if (_enclosingClassIsWidget(decl)) return buildSkips;
    } else if (decl is ConstructorDeclaration) {
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
