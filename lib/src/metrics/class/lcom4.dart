import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'class_metric.dart';

/// LCOM4 (Hitz & Montazeri 1995) — *Lack of Cohesion of Methods*, version 4.
///
/// Treats the class as an undirected graph where each method/constructor is
/// a vertex and an edge exists between two methods when:
///   1. they access at least one field in common, or
///   2. one of them invokes the other.
///
/// `LCOM4` = the number of connected components in that graph. A perfectly
/// cohesive class returns 1; a class that mixes unrelated responsibilities
/// returns higher values, and is a candidate for splitting.
///
/// Field/method matching is name-based on the AST. This trades a small risk
/// of cross-shadow false-positives for not requiring full element resolution
/// inside the class.
class Lcom4 implements ClassMetric {
  const Lcom4();

  @override
  String get id => 'lcom4';

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
    final accessedFields = List.generate(view.methods.length, (_) => <String>{});
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

  FunctionBody? _bodyOf(Declaration decl) {
    if (decl is MethodDeclaration) return decl.body;
    if (decl is ConstructorDeclaration) return decl.body;
    return null;
  }
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
    final fieldNames = <String>{};
    final methods = <Declaration>[];
    final methodIndex = <String, int>{};
    for (final member in cls.body.members) {
      if (member is FieldDeclaration) {
        for (final v in member.fields.variables) {
          fieldNames.add(v.name.lexeme);
        }
      } else if (member is MethodDeclaration && member.body is! EmptyFunctionBody) {
        methodIndex[member.name.lexeme] = methods.length;
        methods.add(member);
      } else if (member is ConstructorDeclaration && member.body is! EmptyFunctionBody) {
        final n = member.name?.lexeme ?? cls.namePart.typeName.lexeme;
        methodIndex[n] = methods.length;
        methods.add(member);
      }
    }
    return _ClassView(
      fieldNames: fieldNames,
      methods: methods,
      methodNameToIndex: methodIndex,
    );
  }
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
  _UnionFind(int n)
      : parent = List<int>.generate(n, (i) => i),
        rank = List<int>.filled(n, 0);

  final List<int> parent;
  final List<int> rank;

  int find(int x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]];
      x = parent[x];
    }
    return x;
  }

  void union(int a, int b) {
    final ra = find(a), rb = find(b);
    if (ra == rb) return;
    if (rank[ra] < rank[rb]) {
      parent[ra] = rb;
    } else if (rank[ra] > rank[rb]) {
      parent[rb] = ra;
    } else {
      parent[rb] = ra;
      rank[ra]++;
    }
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
