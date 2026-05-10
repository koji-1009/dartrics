import 'package:dartrics/src/metrics/test_aware.dart';
import 'package:test/test.dart';

void main() {
  group('TestAware.isTestPath', () {
    test('matches *_test.dart files under test/', () {
      expect(TestAware.isTestPath('test/foo_test.dart'), isTrue);
      expect(TestAware.isTestPath('test/sub/bar_test.dart'), isTrue);
      expect(TestAware.isTestPath('/abs/proj/test/x_test.dart'), isTrue);
    });

    test('matches *_test.dart files under integration_test/', () {
      expect(TestAware.isTestPath('integration_test/app_test.dart'), isTrue);
    });

    test('rejects test/ helpers that lack the _test.dart suffix', () {
      // Helpers under test/ are still production-quality utilities, so
      // they remain under the strict thresholds. This also skips the
      // analyzer_testing harness fixture path
      // (workspace/test/lib/test.dart), which is not real test code.
      expect(TestAware.isTestPath('test/helpers.dart'), isFalse);
      expect(TestAware.isTestPath('test/fixtures/sample.dart'), isFalse);
      expect(TestAware.isTestPath('workspace/test/lib/test.dart'), isFalse);
    });

    test('rejects non-test paths regardless of basename', () {
      expect(TestAware.isTestPath('lib/foo.dart'), isFalse);
      expect(TestAware.isTestPath('lib/test_utils/helper.dart'), isFalse);
      expect(TestAware.isTestPath('bin/dartrics.dart'), isFalse);
      // _test.dart filename outside test/ doesn't earn the relaxation.
      expect(TestAware.isTestPath('lib/foo_test.dart'), isFalse);
    });

    test('normalises Windows separators', () {
      expect(TestAware.isTestPath(r'C:\proj\test\foo_test.dart'), isTrue);
    });
  });

  test('skip sets are populated and disjoint from each other', () {
    expect(TestAware.functionSkips, contains('method-length'));
    expect(TestAware.functionSkips, contains('source-lines-of-code'));
    expect(TestAware.classSkips, contains('class-length'));
    expect(TestAware.classSkips, contains('number-of-methods'));
    // The function and class skip sets target disjoint metric ids by
    // design — function-level skips never apply to class-level metrics
    // and vice versa.
    expect(TestAware.functionSkips.intersection(TestAware.classSkips), isEmpty);
  });
}
