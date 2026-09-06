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

    test('the id does not depend on where the repo is checked out', () {
      final dev = computeViolationId(
        file: '/Users/dev/proj/lib/foo.dart',
        scope: 'Foo.bar',
        metricId: 'cyclomatic-complexity',
        root: '/Users/dev/proj',
      );
      final ci = computeViolationId(
        file: '/home/runner/work/proj/proj/lib/foo.dart',
        scope: 'Foo.bar',
        metricId: 'cyclomatic-complexity',
        root: '/home/runner/work/proj/proj',
      );
      expect(dev, ci);
    });

    test('a rooted absolute path matches the relative form RegressionRow '
        'hashes', () {
      final fromAnalyze = computeViolationId(
        file: '/Users/dev/proj/lib/foo.dart',
        scope: 'Foo.bar',
        metricId: 'cyclomatic-complexity',
        root: '/Users/dev/proj',
      );
      final fromRegression = computeViolationId(
        file: 'lib/foo.dart',
        scope: 'Foo.bar',
        metricId: 'cyclomatic-complexity',
      );
      expect(fromAnalyze, fromRegression);
    });
  });

  group('violationIdPath', () {
    test('relativises a path inside the root', () {
      expect(
        violationIdPath(
          '/Users/dev/proj/lib/foo.dart',
          root: '/Users/dev/proj',
        ),
        'lib/foo.dart',
      );
    });

    test('normalises separators when no root is given', () {
      expect(violationIdPath(r'lib\foo.dart'), 'lib/foo.dart');
    });

    test('resolves a relative file against the root', () {
      expect(
        violationIdPath('lib/foo.dart', root: '/Users/dev/proj'),
        'lib/foo.dart',
      );
    });

    test('leaves a path outside the root alone', () {
      expect(
        violationIdPath('/elsewhere/lib/foo.dart', root: '/Users/dev/proj'),
        '/elsewhere/lib/foo.dart',
      );
    });

    test('a relative root is resolved against the cwd', () {
      // `--root .` is the CLI default, so the common case goes through
      // `p.absolute` before the containment check.
      expect(violationIdPath('lib/foo.dart', root: '.'), 'lib/foo.dart');
    });
  });
}
