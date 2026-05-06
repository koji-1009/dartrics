import 'dart:io';

import 'package:dartrics/src/analyzer_runner.dart';
import 'package:dartrics/src/config/config.dart';
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
}
