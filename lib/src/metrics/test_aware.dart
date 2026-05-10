/// Pure-path helpers used by the metric engine to relax a small set of
/// metrics on test files. Symmetric to [FlutterAware] but file-scoped:
/// the trigger is "this file lives under `test/` or `integration_test/`",
/// not "this declaration is a particular AST shape." Test files use
/// arrange/act/assert blocks that are legitimately long and N-test-method
/// classes — so the size-and-shape lenses fire by default and AI loops
/// churn on them. Cyclomatic / cognitive complexity stay engaged because
/// a branchy test is still hard to read.
abstract final class TestAware {
  /// Path segments that mark the enclosing tree as test code. Directly
  /// matches the standard `dart test` conventions: `test/...` and
  /// `integration_test/...`. Anything under `lib/test_utils/` or named
  /// in user-land is intentionally not auto-relaxed — the dismiss
  /// channel is the right place for those.
  static const Set<String> testDirSegments = {'test', 'integration_test'};

  /// Function- and method-level metrics skipped on test files.
  ///
  /// `method-length` / `source-lines-of-code`: AAA blocks legitimately
  /// exceed the function-body length thresholds calibrated for
  /// production code.
  static const Set<String> functionSkips = {
    'method-length',
    'source-lines-of-code',
  };

  /// Class-level metrics skipped on test files. Test classes legitimately
  /// hold many `@Test` methods spanning a long body.
  static const Set<String> classSkips = {'class-length', 'number-of-methods'};

  /// Returns true when [path] is a conventional dart-test file: it sits
  /// under one of [testDirSegments] (any depth) **and** its basename
  /// ends in `_test.dart`. The basename suffix is the marker `dart test`
  /// itself uses to discover test files; requiring it keeps test
  /// helpers (`test/helpers.dart`) under production-grade thresholds
  /// and prevents the analyzer-testing harness's synthetic
  /// `workspace/test/lib/test.dart` fixture from incorrectly suppressing
  /// the lint rules under unit tests.
  ///
  /// Path separators are normalised so the check works on
  /// Windows-shaped paths too.
  static bool isTestPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/');
    if (segments.isEmpty || !segments.last.endsWith('_test.dart')) {
      return false;
    }
    for (final seg in segments) {
      if (testDirSegments.contains(seg)) return true;
    }
    return false;
  }
}
