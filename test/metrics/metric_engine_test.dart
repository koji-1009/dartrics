import 'dart:io';

import 'package:dartrics/src/analyzer_runner.dart';
import 'package:dartrics/src/config/config.dart';
import 'package:dartrics/src/coverage/lcov_reader.dart';
import 'package:dartrics/src/dismiss/dismissal.dart';
import 'package:dartrics/src/dismiss/dismissal_index.dart';
import 'package:dartrics/src/metrics/metric_engine.dart';
import 'package:dartrics/src/models/analysis_report.dart';
import 'package:dartrics/src/models/source_location.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('engine_test_');
    await Directory('${tempDir.path}/lib/src').create(recursive: true);
    await File('${tempDir.path}/pubspec.yaml').writeAsString('''
name: example_pkg
environment:
  sdk: ^3.10.0
''');
    await File('${tempDir.path}/lib/example_pkg.dart').writeAsString('''
import 'dart:core';
import 'package:meta/meta.dart';
import 'src/types.dart';
import 'unresolvable_relative.dart';
export 'src/types.dart';

int main() {
  final w = Widget('hi');
  print(visibleForTesting);
  return w.length;
}
''');
    await File('${tempDir.path}/lib/src/types.dart').writeAsString('''
abstract class Shape {
  int area();
}

class Widget extends Shape {
  Widget(this.label) {
    if (label.isEmpty) {
      throw ArgumentError('empty label');
    }
  }
  Widget.empty() : label = '' {
    print('empty');
  }
  final String label;
  int get length => label.length;
  @override
  int area() => label.length;
}

mixin Mixable {
  int magic() => 42;
}

extension OnInt on int {
  int twice() => this * 2;
}

extension on String {
  String reversed() => split('').reversed.join();
}

enum Color {
  red,
  green,
  blue;
  String describe() => name;
}
''');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('analyze produces function, class, and library records', () async {
    final runner = AnalyzerRunner(roots: [tempDir.path]);
    final units = await runner.resolveAll();
    final engine = MetricEngine(
      thresholds: const {
        // Warning at 1 fires on every method (base CC = 1); error at 1 fires
        // on the constructor that has an `if`.
        'cyclomatic-complexity': MetricThresholds(warning: 1, error: 2),
      },
    );
    final records = engine.analyzeResolved(units);

    final byKind = <ScopeKind, int>{};
    for (final r in records) {
      byKind.update(r.scope.kind, (n) => n + 1, ifAbsent: () => 1);
    }
    expect(byKind[ScopeKind.function], greaterThan(0));
    expect(byKind[ScopeKind.method], greaterThan(0));
    expect(byKind[ScopeKind.klass], greaterThan(0));
    expect(byKind[ScopeKind.library], greaterThan(0));

    final hasErrorViolation = records.any(
      (r) => r.violations.any((v) => v.severity == Severity.error),
    );
    expect(hasErrorViolation, isTrue);
    final hasWarningViolation = records.any(
      (r) => r.violations.any((v) => v.severity == Severity.warning),
    );
    expect(hasWarningViolation, isTrue);
  });

  test(
    'AnalysisReport.hasSeverityAtLeast reports the worst per-record level',
    () {
      final engine = MetricEngine(
        thresholds: const {
          'cyclomatic-complexity': MetricThresholds(warning: 1, error: 2),
        },
      );
      final report = AnalysisReport(
        version: '1.0',
        metrics: engine.analyzeResolved(const []),
        unused: const [],
      );
      expect(report.hasSeverityAtLeast(Severity.warning), isFalse);
    },
  );

  test('analyze (legacy entrypoint) wraps resolveAll', () async {
    final runner = AnalyzerRunner(roots: [tempDir.path]);
    final records = await MetricEngine().analyze(runner);
    expect(records, isNotEmpty);
  });

  test(
    'experimental metrics (Halstead, MI) are off by default and skipped',
    () async {
      final runner = AnalyzerRunner(roots: [tempDir.path]);
      final units = await runner.resolveAll();
      final records = MetricEngine().analyzeResolved(units);
      final keys = records.expand((r) => r.values.keys).toSet();
      expect(keys, isNot(contains('halstead-volume')));
      // halstead-difficulty / halstead-effort / maintainability-index
      // are not provided — they're derivations of halstead-volume +
      // CC + LOC and add no orthogonal signal.
      // Sanity: the core metrics still land.
      expect(keys, contains('cyclomatic-complexity'));
    },
  );

  test('thresholds.enabled=true opts into an experimental metric', () async {
    final runner = AnalyzerRunner(roots: [tempDir.path]);
    final units = await runner.resolveAll();
    final engine = MetricEngine(
      thresholds: const {'halstead-volume': MetricThresholds(enabled: true)},
    );
    final records = engine.analyzeResolved(units);
    final keys = records.expand((r) => r.values.keys).toSet();
    expect(keys, contains('halstead-volume'));
  });

  test('thresholds.enabled=false disables a default-on metric', () async {
    final runner = AnalyzerRunner(roots: [tempDir.path]);
    final units = await runner.resolveAll();
    final engine = MetricEngine(
      thresholds: const {
        'cyclomatic-complexity': MetricThresholds(enabled: false),
      },
    );
    final records = engine.analyzeResolved(units);
    final keys = records.expand((r) => r.values.keys).toSet();
    expect(keys, isNot(contains('cyclomatic-complexity')));
  });

  test(
    'Flutter aware mode keeps build() measured + skips ctor `number-of-parameters`',
    () async {
      // Contract: Widget.build() is **not** specially skipped — a
      // healthy declarative Container-tree produces zero control-flow
      // signal anyway. The constructor still skips
      // `number-of-parameters` because key + multiple callbacks is the
      // cultural norm.
      final dir = await Directory.systemTemp.createTemp('flutter_engine_');
      addTearDown(() => dir.delete(recursive: true));
      await Directory('${dir.path}/lib').create(recursive: true);
      await File(
        '${dir.path}/pubspec.yaml',
      ).writeAsString('name: example\nenvironment:\n  sdk: ^3.10.0\n');
      await File('${dir.path}/lib/widget.dart').writeAsString('''
class StatelessWidget {}
class Container { Container({this.child}); final Container? child; }

class Hello extends StatelessWidget {
  Hello(this.a, this.b, this.c, this.d, this.e) {
    print(a);
  }
  final int a, b, c, d, e;
  Container build(Object? ctx) {
    return Container(
      child: Container(
        child: Container(
          child: Container(),
        ),
      ),
    );
  }
  Container _helper() {
    return Container();
  }
}
''');
      final runner = AnalyzerRunner(roots: [dir.path]);
      final units = await runner.resolveAll();

      final records = MetricEngine().analyzeResolved(units);

      // build() is measured for every default-on metric, regardless of
      // flutter mode — control-flow nesting on a declarative Widget
      // tree is naturally 0, so the metric doesn't false-positive on
      // healthy code. (method-length is default-off because of its
      // high correlation with SLOC; opt-in only.)
      final buildKeys = records
          .firstWhere((r) => r.scope.name == 'Hello.build')
          .values
          .keys
          .toSet();
      expect(buildKeys, contains('source-lines-of-code'));
      expect(buildKeys, contains('cyclomatic-complexity'));

      // The constructor still skips number-of-parameters under the
      // Flutter-aware default (flutter: true).
      final ctorKeys = records
          .firstWhere(
            (r) =>
                r.scope.name == 'Hello' &&
                r.values.containsKey('cyclomatic-complexity'),
          )
          .values
          .keys
          .toSet();
      expect(ctorKeys, isNot(contains('number-of-parameters')));

      // Pinning flutter:false un-skips the constructor too.
      final strict = MetricEngine(flutter: false).analyzeResolved(units);
      final strictCtor = strict
          .firstWhere(
            (r) =>
                r.scope.name == 'Hello' &&
                r.values.containsKey('number-of-parameters'),
          )
          .values
          .keys
          .toSet();
      expect(strictCtor, contains('number-of-parameters'));

      // Helper methods are measured normally on both paths.
      final helperKeys = records
          .firstWhere((r) => r.scope.name == 'Hello._helper')
          .values
          .keys
          .toSet();
      expect(helperKeys, contains('cyclomatic-complexity'));
    },
  );

  test('CC discounts case arms when the switch subject is sealed', () async {
    // A switch over a sealed type is exhaustive at compile time, so
    // the case arms shouldn't inflate CC the way arbitrary
    // if/else-if branching does. The discount only fires on
    // resolved input — exercise it through the full engine so
    // staticType is available.
    final dir = await Directory.systemTemp.createTemp('sealed_cc_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/lib').create(recursive: true);
    await File(
      '${dir.path}/pubspec.yaml',
    ).writeAsString('name: example\nenvironment:\n  sdk: ^3.10.0\n');
    await File('${dir.path}/lib/state.dart').writeAsString('''
sealed class State {}
class Idle extends State {}
class Loading extends State {}
class Failure extends State {}

String describe(State s) {
  switch (s) {
    case Idle(): return 'idle';
    case Loading(): return 'loading';
    case Failure(): return 'failure';
  }
}

String describeOpen(Object o) {
  switch (o) {
    case int x when x > 0: return 'pos';
    case String s: return s;
  }
  return '';
}

// Switch *expression* form (Dart 3 syntax) over a sealed type —
// the discount must apply here too.
String describeExpr(State s) => switch (s) {
  Idle() => 'idle',
  Loading() => 'loading',
  Failure() => 'failure',
};

// Switch expression over a non-exhaustive subject: arms count.
String describeOpenExpr(int x) => switch (x) {
  0 => 'zero',
  1 => 'one',
  _ => 'many',
};
''');
    final runner = AnalyzerRunner(roots: [dir.path]);
    final units = await runner.resolveAll();
    final records = MetricEngine().analyzeResolved(units);

    // describe() switches over sealed `State` — three case arms
    // should not contribute to CC. Expected: 1 (base).
    final sealedCc = records
        .firstWhere((r) => r.scope.name == 'describe')
        .values['cyclomatic-complexity'];
    expect(sealedCc, 1);

    // describeOpen() switches over `Object` (non-sealed). The two
    // pattern cases each add 1. Expected: 1 + 2 = 3.
    final openCc = records
        .firstWhere((r) => r.scope.name == 'describeOpen')
        .values['cyclomatic-complexity'];
    expect(openCc, 3);

    // describeExpr() uses the switch-expression form over the sealed
    // type. The visitor must apply the discount on this form too.
    final exprCc = records
        .firstWhere((r) => r.scope.name == 'describeExpr')
        .values['cyclomatic-complexity'];
    expect(exprCc, 1);

    // describeOpenExpr() switches over `int` (not exhaustible): the two
    // value arms count, the bare `_` arm is the `default:` equivalent.
    // Expected: 1 + 2 = 3.
    final openExprCc = records
        .firstWhere((r) => r.scope.name == 'describeOpenExpr')
        .values['cyclomatic-complexity'];
    expect(openExprCc, 3);
  });

  test('CC discounts case arms when the switch subject is an enum', () async {
    // Enum subjects are compile-time exhaustive exactly like sealed
    // ones, so the exhaustiveness discount applies to them too — on
    // both switch forms. Resolution is required for the subject's
    // staticType, so exercise it through the full engine.
    final dir = await Directory.systemTemp.createTemp('enum_cc_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/lib').create(recursive: true);
    await File(
      '${dir.path}/pubspec.yaml',
    ).writeAsString('name: example\nenvironment:\n  sdk: ^3.10.0\n');
    await File('${dir.path}/lib/color.dart').writeAsString('''
enum Color { red, green, blue }

String describe(Color c) {
  switch (c) {
    case Color.red: return 'red';
    case Color.green: return 'green';
    case Color.blue: return 'blue';
  }
}

String describeExpr(Color c) => switch (c) {
  Color.red => 'red',
  Color.green => 'green',
  Color.blue => 'blue',
};
''');
    final runner = AnalyzerRunner(roots: [dir.path]);
    final units = await runner.resolveAll();
    final records = MetricEngine().analyzeResolved(units);

    // Both forms dispatch over the enum — no arm contributes to CC.
    final stmtCc = records
        .firstWhere((r) => r.scope.name == 'describe')
        .values['cyclomatic-complexity'];
    expect(stmtCc, 1);

    final exprCc = records
        .firstWhere((r) => r.scope.name == 'describeExpr')
        .values['cyclomatic-complexity'];
    expect(exprCc, 1);
  });

  test('closures are measured as separate records', () async {
    final dir = await Directory.systemTemp.createTemp('closure_records_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/lib').create(recursive: true);
    await File(
      '${dir.path}/pubspec.yaml',
    ).writeAsString('name: example\nenvironment:\n  sdk: ^3.10.0\n');
    await File('${dir.path}/lib/handlers.dart').writeAsString('''
void wire(List<int> xs) {
  xs.forEach((x) {
    if (x > 0 && x < 10) print(x);
  });
  xs.where((x) => x.isEven);
}
''');
    final runner = AnalyzerRunner(roots: [dir.path]);
    final units = await runner.resolveAll();
    final records = MetricEngine().analyzeResolved(units);

    // The enclosing function's CC never saw the closure's branches —
    // now they surface in the closure's own record instead of nowhere.
    final wire = records.firstWhere((r) => r.scope.name == 'wire');
    expect(wire.scope.kind, ScopeKind.function);
    expect(wire.values['cyclomatic-complexity'], 1);

    final first = records.firstWhere((r) => r.scope.name == 'wire.closure#1');
    expect(first.scope.kind, ScopeKind.closure);
    // 1 (base) + if + `&&` inside the first closure's body.
    expect(first.values['cyclomatic-complexity'], 3);

    final second = records.firstWhere((r) => r.scope.name == 'wire.closure#2');
    expect(second.scope.kind, ScopeKind.closure);
    expect(second.values['cyclomatic-complexity'], 1);
  });

  test('closure records respect test-aware skips on test files', () async {
    final dir = await Directory.systemTemp.createTemp('closure_test_aware_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/test').create(recursive: true);
    await File(
      '${dir.path}/pubspec.yaml',
    ).writeAsString('name: example\nenvironment:\n  sdk: ^3.10.0\n');
    await File('${dir.path}/test/sample_test.dart').writeAsString('''
void main() {
  run('case', () {
    if (1 > 0) print('x');
  });
}

void run(String name, void Function() body) => body();
''');
    final runner = AnalyzerRunner(roots: [dir.path]);
    final units = await runner.resolveAll();
    final records = MetricEngine().analyzeResolved(units);

    // Same skip set as named functions on test files: size lenses step
    // aside, complexity stays measured.
    final closure = records.firstWhere((r) => r.scope.name == 'main.closure#1');
    expect(closure.scope.kind, ScopeKind.closure);
    expect(closure.values.keys, isNot(contains('source-lines-of-code')));
    expect(closure.values['cyclomatic-complexity'], 2);
  });

  test('test mode relaxes size lenses on test/-resident files', () async {
    final dir = await Directory.systemTemp.createTemp('test_aware_engine_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/test').create(recursive: true);
    await File(
      '${dir.path}/pubspec.yaml',
    ).writeAsString('name: example\nenvironment:\n  sdk: ^3.10.0\n');
    // A test method that is intentionally tall: AAA blocks legitimately
    // exceed `method-length`'s production-grade thresholds.
    await File('${dir.path}/test/sample_test.dart').writeAsString('''
class SampleTest {
  void test_arrange_act_assert() {
    final x = 1;
    final y = 2;
    final z = 3;
    final a = x + y;
    final b = a + z;
    final c = b * 2;
    if (c > 0) {
      if (c > 5) {
        if (c > 10) {
          if (c > 15) {
            print(c);
          }
        }
      }
    }
  }
  void m1() {}
  void m2() {}
}
''');
    final runner = AnalyzerRunner(roots: [dir.path]);
    final units = await runner.resolveAll();

    // Default mode (test:true) skips method-length / SLOC on the test
    // method; class-length and number-of-methods are skipped on the
    // whole class.
    final defaultRecords = MetricEngine().analyzeResolved(units);
    final fnKeys = defaultRecords
        .firstWhere((r) => r.scope.name == 'SampleTest.test_arrange_act_assert')
        .values
        .keys
        .toSet();
    expect(fnKeys, isNot(contains('method-length')));
    expect(fnKeys, isNot(contains('source-lines-of-code')));
    // Branchy tests are still hard to read, so CC stays measured.
    expect(fnKeys, contains('cyclomatic-complexity'));
    final clsKeys = defaultRecords
        .firstWhere(
          (r) => r.scope.name == 'SampleTest' && r.values.containsKey('lcom4'),
        )
        .values
        .keys
        .toSet();
    expect(clsKeys, isNot(contains('class-length')));
    expect(clsKeys, isNot(contains('number-of-methods')));

    // Pinning test:false re-enables size-and-shape metrics on test
    // files. method-length is default-off, so explicitly opt it in
    // via thresholds for this assertion.
    final strictRecords = MetricEngine(
      test: false,
      thresholds: const {'method-length': MetricThresholds(enabled: true)},
    ).analyzeResolved(units);
    final fnStrict = strictRecords
        .firstWhere((r) => r.scope.name == 'SampleTest.test_arrange_act_assert')
        .values
        .keys
        .toSet();
    expect(fnStrict, contains('method-length'));
    expect(fnStrict, contains('source-lines-of-code'));
    final clsStrict = strictRecords
        .firstWhere(
          (r) => r.scope.name == 'SampleTest' && r.values.containsKey('lcom4'),
        )
        .values
        .keys
        .toSet();
    expect(clsStrict, contains('class-length'));
    expect(clsStrict, contains('number-of-methods'));
  });

  test('test mode applies the cognitive test-DSL discount', () async {
    final dir = await Directory.systemTemp.createTemp('test_dsl_engine_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/test').create(recursive: true);
    await File(
      '${dir.path}/pubspec.yaml',
    ).writeAsString('name: example\nenvironment:\n  sdk: ^3.10.0\n');
    // The declarative group()/test() shape: every branch sits two
    // closures deep, so without the discount it accrues to main() at
    // inflated nesting.
    await File('${dir.path}/test/dsl_test.dart').writeAsString('''
void group(String name, void Function() body) { body(); }
void test(String name, void Function() body) { body(); }

void main() {
  group('g', () {
    test('a', () {
      if (1 > 0) {
        if (2 > 1) {
          if (3 > 2) {
            print('deep');
          }
        }
      }
    });
  });
}
''');
    final runner = AnalyzerRunner(roots: [dir.path]);
    final units = await runner.resolveAll();

    // Default (test:true): registration callbacks are data handed to
    // the DSL, not control flow of main.
    final relaxed = MetricEngine().analyzeResolved(units);
    final mainCog = relaxed
        .firstWhere((r) => r.scope.name == 'main')
        .values['cognitive-complexity'];
    expect(mainCog, 0);

    // test:false restores the spec behavior — the if-ladder accrues at
    // closure-inflated nesting: (1+2) + (1+3) + (1+4) = 12.
    final strict = MetricEngine(test: false).analyzeResolved(units);
    final strictCog = strict
        .firstWhere((r) => r.scope.name == 'main')
        .values['cognitive-complexity'];
    expect(strictCog, 12);
  });

  group('coverage-aware violations', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('engine_cov_');
      await Directory('${dir.path}/lib').create();
      await File(
        '${dir.path}/pubspec.yaml',
      ).writeAsString('name: example\nenvironment:\n  sdk: ^3.10.0\n');
      await File('${dir.path}/lib/foo.dart').writeAsString('''
int branchy(int x) {
  if (x > 0) return 1;
  if (x < 0) return -1;
  if (x == 0) return 0;
  return 99;
}
''');
    });

    tearDown(() => dir.delete(recursive: true));

    test('attaches coverage and tags justified CC when branch ≥ 0.8', () async {
      final lcovPath = '${dir.path}/lib/foo.dart';
      final coverage = CoverageIndex.parse('''
SF:$lcovPath
DA:1,1
DA:2,1
DA:3,1
DA:4,1
DA:5,1
DA:6,1
DA:7,1
BRDA:2,0,0,3
BRDA:2,0,1,4
BRDA:3,0,0,2
BRDA:3,0,1,5
BRDA:4,0,0,3
BRDA:4,0,1,3
end_of_record
''');
      final runner = AnalyzerRunner(roots: [dir.path]);
      final units = await runner.resolveAll();
      final engine = MetricEngine(
        thresholds: const {
          'cyclomatic-complexity': MetricThresholds(warning: 1),
        },
        coverage: coverage,
      );
      final records = engine.analyzeResolved(units);
      final fn = records.firstWhere((r) => r.scope.name == 'branchy');
      final v = fn.violations.firstWhere(
        (v) => v.metricId == 'cyclomatic-complexity',
      );
      expect(v.scopeCoverage, 1.0);
      expect(v.scopeBranchCoverage, 1.0);
      expect(v.complexityJustified, isTrue);
      expect(v.complexityJustifiedBy, 'branch');
      expect(v.complexityJustifiedThreshold, 0.8);
    });

    test('does not tag complexityJustified when coverage is low', () async {
      final lcovPath = '${dir.path}/lib/foo.dart';
      final coverage = CoverageIndex.parse('''
SF:$lcovPath
DA:1,1
DA:2,1
DA:3,0
DA:4,0
DA:5,0
DA:6,0
DA:7,1
end_of_record
''');
      final runner = AnalyzerRunner(roots: [dir.path]);
      final units = await runner.resolveAll();
      final engine = MetricEngine(
        thresholds: const {
          'cyclomatic-complexity': MetricThresholds(warning: 1),
        },
        coverage: coverage,
      );
      final records = engine.analyzeResolved(units);
      final fn = records.firstWhere((r) => r.scope.name == 'branchy');
      final v = fn.violations.firstWhere(
        (v) => v.metricId == 'cyclomatic-complexity',
      );
      expect(v.complexityJustified, isFalse);
      expect(v.complexityJustifiedBy, isNull);
      expect(v.complexityJustifiedThreshold, isNull);
      expect(v.scopeCoverage, lessThan(0.95));
    });

    test('falls back to line coverage when no BRDA records', () async {
      final lcovPath = '${dir.path}/lib/foo.dart';
      // 95%+ line coverage, no branch records.
      final coverage = CoverageIndex.parse('''
SF:$lcovPath
DA:1,1
DA:2,1
DA:3,1
DA:4,1
DA:5,1
DA:6,1
DA:7,1
end_of_record
''');
      final runner = AnalyzerRunner(roots: [dir.path]);
      final units = await runner.resolveAll();
      final engine = MetricEngine(
        thresholds: const {
          'cyclomatic-complexity': MetricThresholds(warning: 1),
        },
        coverage: coverage,
      );
      final records = engine.analyzeResolved(units);
      final fn = records.firstWhere((r) => r.scope.name == 'branchy');
      final v = fn.violations.firstWhere(
        (v) => v.metricId == 'cyclomatic-complexity',
      );
      expect(v.scopeBranchCoverage, isNull);
      expect(v.complexityJustified, isTrue);
      expect(v.complexityJustifiedBy, 'line');
      expect(v.complexityJustifiedThreshold, 0.95);
    });

    test('non-justifiable metrics never get the tag', () async {
      final lcovPath = '${dir.path}/lib/foo.dart';
      final coverage = CoverageIndex.parse('''
SF:$lcovPath
DA:1,1
DA:2,1
DA:3,1
DA:4,1
DA:5,1
DA:6,1
DA:7,1
end_of_record
''');
      final runner = AnalyzerRunner(roots: [dir.path]);
      final units = await runner.resolveAll();
      final engine = MetricEngine(
        thresholds: const {
          // method-length is default-off; opt in for this assertion.
          'method-length': MetricThresholds(enabled: true, warning: 1),
        },
        coverage: coverage,
      );
      final records = engine.analyzeResolved(units);
      final fn = records.firstWhere((r) => r.scope.name == 'branchy');
      final v = fn.violations.firstWhere((v) => v.metricId == 'method-length');
      expect(v.scopeCoverage, isNotNull);
      expect(v.complexityJustified, isFalse);
    });
  });

  group('dismissal attachment', () {
    late Directory dir;
    late String filePath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('engine_dismiss_');
      await Directory('${dir.path}/lib').create();
      await File(
        '${dir.path}/pubspec.yaml',
      ).writeAsString('name: example\nenvironment:\n  sdk: ^3.10.0\n');
      filePath = '${dir.path}/lib/foo.dart';
      await File(filePath).writeAsString('''
int branchy(int x) {
  if (x > 0) return 1;
  if (x < 0) return -1;
  if (x == 0) return 0;
  return 99;
}
''');
    });

    tearDown(() => dir.delete(recursive: true));

    Future<List<MetricRecord>> runWith({
      required DismissalIndex index,
      DismissalConfig config = const DismissalConfig(
        commentSource: true,
        yamlSource: true,
      ),
      void Function(Dismissal, String)? onReject,
    }) async {
      final runner = AnalyzerRunner(roots: [dir.path]);
      final units = await runner.resolveAll();
      final engine = MetricEngine(
        thresholds: const {
          'cyclomatic-complexity': MetricThresholds(warning: 1),
        },
        dismissals: index,
        dismissalConfig: config,
        onDismissalRejection: onReject,
      );
      return engine.analyzeResolved(units);
    }

    test('attaches dismiss metadata when entry passes validation', () async {
      final at = DateTime.utc(2026, 5, 6, 19, 14);
      final index = DismissalIndex.build(
        comments: const [],
        yaml: [
          Dismissal(
            file: filePath,
            scope: 'branchy',
            metricId: 'cyclomatic-complexity',
            reason: 'switching on int values keeps intent local',
            source: DismissalSource.yaml,
            by: 'claude',
            at: at,
          ),
        ],
      );
      final records = await runWith(index: index);
      final v = records
          .firstWhere((r) => r.scope.name == 'branchy')
          .violations
          .firstWhere((v) => v.metricId == 'cyclomatic-complexity');
      expect(v.dismissed, isTrue);
      expect(v.dismissReason, 'switching on int values keeps intent local');
      expect(v.dismissedBy, 'claude');
      expect(v.dismissedAt, at);
      expect(v.dismissedFrom, DismissalSource.yaml);
      expect(v.dismissalRejected, isNull);
    });

    test('rejects too-short reason and surfaces dismissalRejected', () async {
      Dismissal? rejectedDismissal;
      String? rejectedReason;
      final index = DismissalIndex.build(
        comments: [
          Dismissal(
            file: filePath,
            scope: 'branchy',
            metricId: 'cyclomatic-complexity',
            reason: 'short',
            source: DismissalSource.comment,
          ),
        ],
        yaml: const [],
      );
      final records = await runWith(
        index: index,
        onReject: (d, r) {
          rejectedDismissal = d;
          rejectedReason = r;
        },
      );
      final v = records
          .firstWhere((r) => r.scope.name == 'branchy')
          .violations
          .firstWhere((v) => v.metricId == 'cyclomatic-complexity');
      expect(v.dismissed, isFalse);
      expect(v.dismissalRejected, contains('reason too short'));
      expect(rejectedDismissal?.scope, 'branchy');
      expect(rejectedReason, contains('reason too short'));
    });

    test('empty index leaves violations untouched', () async {
      final records = await runWith(index: DismissalIndex.empty());
      final v = records
          .firstWhere((r) => r.scope.name == 'branchy')
          .violations
          .firstWhere((v) => v.metricId == 'cyclomatic-complexity');
      expect(v.dismissed, isFalse);
      expect(v.dismissalRejected, isNull);
      expect(v.dismissedFrom, isNull);
    });

    test('every emitted violation carries a 16-hex id', () async {
      final records = await runWith(index: DismissalIndex.empty());
      final fn = records.firstWhere((r) => r.scope.name == 'branchy');
      for (final v in fn.violations) {
        expect(v.id, hasLength(16));
        expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(v.id), isTrue);
      }
    });
  });

  group('firedExplanations', () {
    // Lightweight fixture builder: a single MetricRecord at [scope.kind]
    // carrying one violation with [metricId]. The other fields are not
    // exercised by `firedExplanations`, so the boilerplate stays minimal.
    MetricRecord recordFiring(ScopeKind kind, String metricId) => MetricRecord(
      file: 'lib/foo.dart',
      scope: ScopeRef(
        kind: kind,
        name: 'x',
        location: const SourceLocation(
          path: 'lib/foo.dart',
          line: 1,
          column: 1,
        ),
      ),
      values: const {},
      violations: [
        MetricViolation(
          metricId: metricId,
          severity: Severity.warning,
          threshold: 0,
        ),
      ],
    );

    test('walks function, class, and library calculator lists', () {
      // One violation in each of the three scope kinds, with metric ids
      // that exist in the default lists. firedExplanations should emit
      // exactly those three entries, in calculator-declaration order.
      final engine = MetricEngine();
      final entries = engine.firedExplanations([
        recordFiring(ScopeKind.function, 'cyclomatic-complexity'),
        recordFiring(ScopeKind.klass, 'lcom4'),
        recordFiring(ScopeKind.library, 'instability'),
      ]);
      expect(entries.map((e) => e.metricId).toList(), [
        'cyclomatic-complexity',
        'lcom4',
        'instability',
      ]);
      // Spot-check that rationale + references survive — they come
      // straight from the metric calculator without a Map lookup.
      expect(
        entries.first.rationale,
        contains(''), // any non-empty rationale string is fine
      );
      expect(entries.first.rationale.isNotEmpty, isTrue);
    });

    test('returns const [] when no violation fired', () {
      // The early-return on empty firedIds keeps the post-condition
      // (every entry corresponds to a fired metric) trivially true and
      // dodges the per-list scans.
      expect(MetricEngine().firedExplanations(const []), isEmpty);
      expect(
        MetricEngine().firedExplanations(const [
          MetricRecord(
            file: 'lib/foo.dart',
            scope: ScopeRef(
              kind: ScopeKind.function,
              name: 'x',
              location: SourceLocation(
                path: 'lib/foo.dart',
                line: 1,
                column: 1,
              ),
            ),
            values: {},
            violations: [], // no violation ⇒ nothing to explain
          ),
        ]),
        isEmpty,
      );
    });

    test('dedupes when the same metric fires across multiple scopes', () {
      // Two records, both with cyclomatic-complexity violations.
      // firedExplanations should emit one entry, not two.
      final engine = MetricEngine();
      final entries = engine.firedExplanations([
        recordFiring(ScopeKind.function, 'cyclomatic-complexity'),
        recordFiring(ScopeKind.function, 'cyclomatic-complexity'),
      ]);
      expect(entries, hasLength(1));
      expect(entries.single.metricId, 'cyclomatic-complexity');
    });
  });
}
