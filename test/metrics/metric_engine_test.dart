import 'dart:io';

import 'package:dartrics/src/analyzer_runner.dart';
import 'package:dartrics/src/config/config.dart';
import 'package:dartrics/src/coverage/lcov_reader.dart';
import 'package:dartrics/src/dismiss/dismissal.dart';
import 'package:dartrics/src/dismiss/dismissal_index.dart';
import 'package:dartrics/src/metrics/metric_engine.dart';
import 'package:dartrics/src/models/analysis_report.dart';
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
      expect(keys, isNot(contains('halstead-difficulty')));
      expect(keys, isNot(contains('halstead-effort')));
      expect(keys, isNot(contains('maintainability-index')));
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

  test('flutter mode skips Widget.build() length + nesting', () async {
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

    // Default mode includes everything for build() and the constructor.
    final defaultRecords = MetricEngine().analyzeResolved(units);
    final buildKeys = defaultRecords
        .firstWhere((r) => r.scope.name == 'Hello.build')
        .values
        .keys
        .toSet();
    expect(buildKeys, contains('maximum-nesting-level'));
    expect(buildKeys, contains('method-length'));
    final ctorKeys = defaultRecords
        .firstWhere(
          (r) =>
              r.scope.name == 'Hello' &&
              r.values.containsKey('number-of-parameters'),
        )
        .values
        .keys
        .toSet();
    expect(ctorKeys, contains('number-of-parameters'));

    // Flutter mode skips them on build()/ctor but keeps helper methods.
    final flutterRecords = MetricEngine(flutter: true).analyzeResolved(units);
    final fBuildKeys = flutterRecords
        .firstWhere((r) => r.scope.name == 'Hello.build')
        .values
        .keys
        .toSet();
    expect(fBuildKeys, isNot(contains('maximum-nesting-level')));
    expect(fBuildKeys, isNot(contains('method-length')));
    expect(fBuildKeys, contains('cyclomatic-complexity'));
    final fHelperKeys = flutterRecords
        .firstWhere((r) => r.scope.name == 'Hello._helper')
        .values
        .keys
        .toSet();
    expect(fHelperKeys, contains('maximum-nesting-level'));
    final fCtorKeys = flutterRecords
        .firstWhere(
          (r) =>
              r.scope.name == 'Hello' &&
              r.values.containsKey('cyclomatic-complexity'),
        )
        .values
        .keys
        .toSet();
    expect(fCtorKeys, isNot(contains('number-of-parameters')));
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
        thresholds: const {'method-length': MetricThresholds(warning: 1)},
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
  });
}
