import 'package:dartrics/src/metrics/metric_engine.dart';
import 'package:test/test.dart';

void main() {
  group('computeViolationId', () {
    test('returns the same id for the same triple', () {
      final a = computeViolationId(
        file: 'lib/foo.dart',
        scope: 'Foo.bar',
        metricId: 'cyclomatic-complexity',
      );
      final b = computeViolationId(
        file: 'lib/foo.dart',
        scope: 'Foo.bar',
        metricId: 'cyclomatic-complexity',
      );
      expect(a, b);
      expect(a, hasLength(16));
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(a), isTrue);
    });

    test('changing any component yields a different id', () {
      final base = computeViolationId(
        file: 'lib/foo.dart',
        scope: 'Foo.bar',
        metricId: 'cyclomatic-complexity',
      );
      expect(
        computeViolationId(
          file: 'lib/other.dart',
          scope: 'Foo.bar',
          metricId: 'cyclomatic-complexity',
        ),
        isNot(base),
      );
      expect(
        computeViolationId(
          file: 'lib/foo.dart',
          scope: 'Foo.baz',
          metricId: 'cyclomatic-complexity',
        ),
        isNot(base),
      );
      expect(
        computeViolationId(
          file: 'lib/foo.dart',
          scope: 'Foo.bar',
          metricId: 'method-length',
        ),
        isNot(base),
      );
    });

    test('Windows-style absolute paths are not ambiguous', () {
      // Pipe-delimited input means a literal `:` inside the file path
      // (e.g. `C:/foo.dart`) cannot collide with a scope that starts
      // with `/foo.dart`.
      final winPath = computeViolationId(
        file: r'C:\proj\lib\foo.dart',
        scope: 'fn',
        metricId: 'cc',
      );
      final colonScope = computeViolationId(
        file: 'C',
        scope: r'\proj\lib\foo.dart|fn',
        metricId: 'cc',
      );
      expect(winPath, isNot(colonScope));
    });
  });
}
