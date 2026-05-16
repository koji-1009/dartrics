import 'dart:io';

import 'package:dartrics/src/analyzer_runner.dart';
import 'package:dartrics/src/models/call_graph_inspection.dart';
import 'package:dartrics/src/unused/resolved_reachability.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('call_graph_inspect_');
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

  test('walks upstream callers within depth and reports edge counts', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
void main() {
  caller();
  caller();
}

void caller() {
  anchor();
}

void anchor() {}
''');
    final result = inspectCallGraph(
      await resolveAll(),
      query: 'anchor',
      depth: 2,
      direction: InspectionDirection.up,
    );
    expect(result.matches, hasLength(1));
    final match = result.matches.single;
    expect(match.anchor.scope.name, 'anchor');
    expect(match.upstream.map((n) => (n.depth, n.signal.scope.name)), [
      (1, 'caller'),
      (2, 'main'),
    ]);
    // `main` invokes `caller` twice — that's the edge count on the
    // hop from `caller` (depth 1) to `main` (depth 2).
    expect(match.upstream[1].incomingEdgeCount, 2);
    expect(match.downstream, isEmpty);
  });

  test(
    'walks downstream callees and surfaces multi-call edge weights',
    () async {
      await File('${dir.path}/lib/foo.dart').writeAsString('''
void main() => caller();

void caller() {
  target();
  target();
  target();
}

void target() {}
''');
      final result = inspectCallGraph(
        await resolveAll(),
        query: 'caller',
        depth: 1,
        direction: InspectionDirection.down,
      );
      final match = result.matches.single;
      expect(match.upstream, isEmpty);
      expect(match.downstream, hasLength(1));
      expect(match.downstream.single.signal.scope.name, 'target');
      expect(match.downstream.single.incomingEdgeCount, 3);
    },
  );

  test(
    'direction=both returns the union with each side walked separately',
    () async {
      await File('${dir.path}/lib/foo.dart').writeAsString('''
void main() => mid();
void mid() => leaf();
void leaf() {}
''');
      final result = inspectCallGraph(
        await resolveAll(),
        query: 'mid',
        depth: 1,
        direction: InspectionDirection.both,
      );
      final match = result.matches.single;
      expect(match.upstream.map((n) => n.signal.scope.name), ['main']);
      expect(match.downstream.map((n) => n.signal.scope.name), ['leaf']);
    },
  );

  test(
    'returns one match per homonym when the symbol resolves multiply',
    () async {
      await File('${dir.path}/lib/foo.dart').writeAsString('''
import 'src/a.dart';
import 'src/b.dart';

void main() {
  A().work();
  B().work();
}
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
      final result = inspectCallGraph(
        await resolveAll(),
        query: 'A.work',
        depth: 1,
        direction: InspectionDirection.up,
      );
      expect(result.matches, hasLength(1));
      expect(result.matches.single.anchor.scope.name, 'A.work');
    },
  );

  test(
    'upstream walk sorts by fanInCallers so the most-connected caller comes first',
    () async {
      // Two callers of `target` at depth 1; `hub` is itself called
      // from a couple of additional sites, so `hub.fanInCallers > leaf.fanInCallers`.
      // The upstream walk should surface `hub` ahead of `leaf`.
      await File('${dir.path}/lib/foo.dart').writeAsString('''
void main() {
  callHub();
  callHubAgain();
  hub();
  leaf();
}

void callHub() => hub();
void callHubAgain() => hub();

void hub() => target();
void leaf() => target();

void target() {}
''');
      final result = inspectCallGraph(
        await resolveAll(),
        query: 'target',
        depth: 1,
        direction: InspectionDirection.up,
      );
      final upstream = result.matches.single.upstream;
      expect(upstream.map((n) => n.signal.scope.name), ['hub', 'leaf']);
    },
  );

  test(
    'downstream walk sorts by fanOutCallees so the widest callee comes first',
    () async {
      // The anchor `root` calls two helpers; `wide` calls three further
      // helpers while `narrow` calls one. The downstream walk should
      // surface `wide` before `narrow` because the comparator falls
      // through to fanOutCallees when fanInCallers ties.
      await File('${dir.path}/lib/foo.dart').writeAsString('''
void main() => root();

void root() {
  wide();
  narrow();
}

void wide() {
  a();
  b();
  c();
}

void narrow() {
  z();
}

void a() {}
void b() {}
void c() {}
void z() {}
''');
      final result = inspectCallGraph(
        await resolveAll(),
        query: 'root',
        depth: 1,
        direction: InspectionDirection.down,
      );
      final downstream = result.matches.single.downstream;
      expect(downstream.map((n) => n.signal.scope.name), ['wide', 'narrow']);
    },
  );

  test('returns no matches when the symbol does not exist', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
void main() {}
''');
    final result = inspectCallGraph(
      await resolveAll(),
      query: 'doesNotExist',
      depth: 2,
      direction: InspectionDirection.both,
    );
    expect(result.matches, isEmpty);
  });

  test('rejects depth < 1 so callers cannot ask for an empty walk', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
void main() {}
''');
    expect(
      () => inspectCallGraph(
        [],
        query: 'main',
        depth: 0,
        direction: InspectionDirection.both,
      ),
      throwsArgumentError,
    );
  });
}
