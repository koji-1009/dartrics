import 'dart:io';

import 'package:dartrics/src/analyzer_runner.dart';
import 'package:dartrics/src/models/analysis_report.dart';
import 'package:dartrics/src/models/call_graph_signal.dart';
import 'package:dartrics/src/unused/resolved_reachability.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('call_graph_signals_');
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

  CallGraphSignal signalFor(List<CallGraphSignal> signals, String scopeName) {
    final match = signals.where((s) => s.scope.name == scopeName).toList();
    if (match.isEmpty) {
      fail(
        'no signal for scope "$scopeName" in: '
        '${signals.map((s) => s.scope.name).toList()}',
      );
    }
    if (match.length > 1) {
      fail(
        'multiple signals for scope "$scopeName" '
        '(homonyms not disambiguated by this helper)',
      );
    }
    return match.single;
  }

  test('counts edges not unique callees on the fan-out side', () async {
    // `caller` invokes `target` three times. Element-resolved fan-out
    // should record callees=1, calls=3 — not callees=3.
    await File('${dir.path}/lib/foo.dart').writeAsString('''
void main() => caller();

void caller() {
  target();
  target();
  target();
}

void target() {}
''');
    final signals = computeCallGraphSignals(await resolveAll());
    final caller = signalFor(signals, 'caller');
    expect(caller.fanOutCallees, 1);
    expect(caller.fanOutCalls, 3);
    final target = signalFor(signals, 'target');
    expect(target.fanInCallers, 1);
    expect(target.fanInCalls, 3);
  });

  test('homonym methods on different classes are independent', () async {
    // `A.work` and `B.work` are tracked as separate nodes — the
    // simple-name pass would have collapsed them; element-resolved
    // signals must not.
    await File('${dir.path}/lib/foo.dart').writeAsString('''
import 'src/a.dart';
import 'src/b.dart';

void main() {
  A().work();
}

void useB(B b) => b;
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
    final signals = computeCallGraphSignals(await resolveAll());
    final aWork = signals.where((s) => s.scope.name == 'A.work').toList();
    final bWork = signals.where((s) => s.scope.name == 'B.work').toList();
    expect(aWork, hasLength(1));
    expect(bWork, hasLength(1));
    expect(aWork.single.fanInCallers, 1);
    expect(bWork.single.fanInCallers, 0);
  });

  test('SDK / dependency references are excluded from fan-out', () async {
    // `print` and `List` resolve to SDK elements — they should be
    // ignored when computing fan-out for `useStd`.
    await File('${dir.path}/lib/foo.dart').writeAsString('''
void main() => useStd();

void useStd() {
  print('a');
  print('b');
  final xs = <int>[1, 2, 3];
  print(xs.length);
}
''');
    final signals = computeCallGraphSignals(await resolveAll());
    final useStd = signalFor(signals, 'useStd');
    expect(useStd.fanOutCallees, 0);
    expect(useStd.fanOutCalls, 0);
  });

  test('a declared-but-never-called public function shows fan-in 0 '
      'so callers can flag it as an unwired implementation', () async {
    await File('${dir.path}/lib/foo.dart').writeAsString('''
void main() {}

void unwiredHelper() {}
''');
    final signals = computeCallGraphSignals(await resolveAll());
    final orphan = signalFor(signals, 'unwiredHelper');
    expect(orphan.fanInCallers, 0);
    expect(orphan.fanInCalls, 0);
  });

  test(
    'ScopeKind maps class members to method and top-level to function',
    () async {
      await File('${dir.path}/lib/foo.dart').writeAsString('''
void topLevel() {}

class C {
  void member() {}
}
''');
      final signals = computeCallGraphSignals(await resolveAll());
      final top = signalFor(signals, 'topLevel');
      expect(top.scope.kind, ScopeKind.function);
      final member = signalFor(signals, 'C.member');
      expect(member.scope.kind, ScopeKind.method);
    },
  );

  test(
    'ScopeKind covers extensions, typedefs, class fields, and enum constants',
    () async {
      await File('${dir.path}/lib/foo.dart').writeAsString('''
typedef Predicate = bool Function(int);

enum Mode { fast, slow }

class C {
  int counter = 0;
}

extension OnInt on int {
  int doubled() => this * 2;
}

void main() {
  bool Function(int) p = (n) => n > 0;
  Predicate q = p;
  q(1);
  Mode m = Mode.fast;
  print(m);
  final c = C();
  c.counter = 1;
  print(1.doubled());
}
''');
      final signals = computeCallGraphSignals(await resolveAll());
      // Typedef stays a function-scope declaration.
      expect(signalFor(signals, 'Predicate').scope.kind, ScopeKind.function);
      // Class fields and enum values are exposed as method-scope
      // because they belong to an enclosing type.
      expect(signalFor(signals, 'C.counter').scope.kind, ScopeKind.method);
      expect(signalFor(signals, 'Mode.fast').scope.kind, ScopeKind.method);
      // Extensions come back as klass-scope.
      expect(signalFor(signals, 'OnInt').scope.kind, ScopeKind.klass);
    },
  );
}
