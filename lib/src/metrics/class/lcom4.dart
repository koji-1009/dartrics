import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'class_metric.dart';

/// LCOM4 — *Lack of Cohesion of Methods*. Connected-components variant
/// introduced by Hitz & Montazeri (1995); the "LCOM4" label is a later
/// community convention (Henderson-Sellers' LCOM1–LCOM5 numbering),
/// not the authors' own naming.
///
/// Treats the class as an undirected graph where each method/constructor is
/// a vertex and an edge exists between two methods when:
///   1. they access at least one field in common, or
///   2. one of them invokes the other.
///
/// The metric is the number of connected components in that graph. A
/// perfectly cohesive class returns 1; a class that mixes unrelated
/// responsibilities returns higher values, and is a candidate for splitting.
///
/// Field/method matching is name-based on the AST. This trades a small risk
/// of cross-shadow false-positives for not requiring full element resolution
/// inside the class.
class Lcom4 extends ClassMetric {
  const Lcom4();

  @override
  String get id => 'lcom4';

  @override
  String get rationale =>
      'Connected-components cohesion (Hitz & Montazeri, *Measuring '
      'Coupling and Cohesion in Object-Oriented Systems*, 1995; '
      'widely labeled "LCOM4" in the secondary literature) builds an '
      'undirected graph where each method is a vertex and an edge '
      'exists when two methods share a field or one calls the other. '
      'The metric is the number of connected components: 1 means a '
      'perfectly cohesive class, anything higher hints that unrelated '
      'responsibilities are coexisting in one type. Hitz and Montazeri '
      'argue this reading is closer to a designer\'s intuition than '
      'the original LCOM1 score.\n\n'
      'Dart deviation: only methods declared on the class itself are '
      'vertices in the graph — mixin-applied methods and inherited '
      'methods are invisible. The trade-off avoids the false '
      'positives a "include everything that resolves on this type" '
      'reading would create, but it does mean methods that cohere '
      'only via a mixin appear as isolated components. See '
      '`doc/calibration.md` for the full deviation rationale.';

  @override
  List<String> get refactorHints => const [
    'Extract each connected component into its own class — that drops LCOM4 to 1 for both halves.',
    'Promote shared fields into a value object that both groups of methods accept as a parameter.',
    'Delete vestigial methods that don\'t touch any field — they usually belong on a static utility instead.',
  ];

  @override
  List<String> get references => const [
    'Hitz, M., & Montazeri, B. (1995). Measuring Coupling and Cohesion in Object-Oriented Systems. Proc. International Symposium on Applied Corporate Computing.',
  ];

  @override
  num compute(ClassMetricInput input) {
    final view = _ClassView.of(input.declaration);
    if (view.methods.length <= 1) return view.methods.length;

    final accesses = _collectAccesses(view);
    final uf = _UnionFind(view.methods.length)
      ..unionBySharedField(accesses.byField)
      ..unionByDirectCall(accesses.calls);
    return uf.componentCount();
  }

  _Accesses _collectAccesses(_ClassView view) {
    final accessedFields = List.generate(
      view.methods.length,
      (_) => <String>{},
    );
    final calledMethods = List.generate(view.methods.length, (_) => <int>{});
    for (var i = 0; i < view.methods.length; i++) {
      final body = _bodyOf(view.methods[i]);
      if (body == null) continue;
      final visitor = _AccessVisitor(
        fields: view.fieldNames,
        methodIndex: view.methodNameToIndex,
      );
      body.accept(visitor);
      accessedFields[i] = visitor.fieldsAccessed;
      calledMethods[i] = visitor.methodsCalled..remove(i);
    }
    final byField = <String, List<int>>{};
    for (var i = 0; i < accessedFields.length; i++) {
      for (final f in accessedFields[i]) {
        byField.putIfAbsent(f, () => <int>[]).add(i);
      }
    }
    return _Accesses(byField: byField, calls: calledMethods);
  }

  FunctionBody? _bodyOf(Declaration decl) => switch (decl) {
    MethodDeclaration(:final body) => body,
    ConstructorDeclaration(:final body) => body,
    _ => null,
  };
}

class _ClassView {
  _ClassView({
    required this.fieldNames,
    required this.methods,
    required this.methodNameToIndex,
  });

  final Set<String> fieldNames;
  final List<Declaration> methods;
  final Map<String, int> methodNameToIndex;

  static _ClassView of(ClassDeclaration cls) {
    final builder = _ClassViewBuilder(cls);
    for (final member in cls.body.members) {
      builder.ingest(member);
    }
    return builder.build();
  }
}

class _ClassViewBuilder {
  _ClassViewBuilder(this.owner);

  final ClassDeclaration owner;
  final Set<String> fieldNames = {};
  final List<Declaration> methods = [];
  final Map<String, int> methodIndex = {};

  void ingest(ClassMember member) {
    switch (member) {
      case FieldDeclaration(:final fields):
        for (final v in fields.variables) {
          fieldNames.add(v.name.lexeme);
        }
      case MethodDeclaration(:final body, :final name)
          when body is! EmptyFunctionBody:
        methodIndex[name.lexeme] = methods.length;
        methods.add(member);
      case ConstructorDeclaration(:final body, :final name)
          when body is! EmptyFunctionBody:
        methodIndex[name?.lexeme ?? owner.namePart.typeName.lexeme] =
            methods.length;
        methods.add(member);
      // Empty-bodied methods/constructors and other ClassMember variants
      // (e.g. external/abstract decls) don't contribute to LCOM4 cohesion.
      case _:
    }
  }

  _ClassView build() => _ClassView(
    fieldNames: fieldNames,
    methods: methods,
    methodNameToIndex: methodIndex,
  );
}

class _Accesses {
  _Accesses({required this.byField, required this.calls});
  final Map<String, List<int>> byField;
  final List<Set<int>> calls;
}

class _AccessVisitor extends RecursiveAstVisitor<void> {
  _AccessVisitor({required this.fields, required this.methodIndex});

  final Set<String> fields;
  final Map<String, int> methodIndex;
  final fieldsAccessed = <String>{};
  final methodsCalled = <int>{};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final n = node.name;
    if (fields.contains(n)) fieldsAccessed.add(n);
    final idx = methodIndex[n];
    if (idx != null) methodsCalled.add(idx);
    super.visitSimpleIdentifier(node);
  }
}

class _UnionFind {
  _UnionFind(int n) : parent = List<int>.generate(n, (i) => i);

  final List<int> parent;

  int find(int x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]];
      x = parent[x];
    }
    return x;
  }

  void union(int a, int b) {
    final ra = find(a);
    final rb = find(b);
    if (ra != rb) parent[rb] = ra;
  }

  int componentCount() {
    final roots = <int>{};
    for (var i = 0; i < parent.length; i++) {
      roots.add(find(i));
    }
    return roots.length;
  }
}

extension on _UnionFind {
  void unionBySharedField(Map<String, List<int>> byField) {
    for (final group in byField.values) {
      for (var i = 1; i < group.length; i++) {
        union(group[0], group[i]);
      }
    }
  }

  void unionByDirectCall(List<Set<int>> calls) {
    for (var i = 0; i < calls.length; i++) {
      for (final j in calls[i]) {
        union(i, j);
      }
    }
  }
}
