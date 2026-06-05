// `analyzer_testing` requires snake_case `test_*` instance methods, which
// trip the project's strict naming and avoid_void_async lints.
// ignore_for_file: non_constant_identifier_names, avoid_void_async

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:dartrics/src/lint/rules/cognitive_complexity_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(CognitiveComplexityRuleTest);
    defineReflectiveTests(CognitiveComplexityRuleTestDslTest);
  });
}

@reflectiveTest
class CognitiveComplexityRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = CognitiveComplexityRule();
    super.setUp();
  }

  @override
  String get analysisRule => 'dartrics_cognitive_complexity';

  void test_simpleFunction_noLint() async {
    await assertNoDiagnostics(r'''
int add(int a, int b) => a + b;
''');
  }

  void test_atThreshold_lint() async {
    // Five nested ifs: 1 + 2 + 3 + 4 + 5 = 15 cognitive complexity.
    await assertDiagnostics(
      r'''
void f(int x) {
  if (x > 0) {
    if (x > 1) {
      if (x > 2) {
        if (x > 3) {
          if (x > 4) {
            print('deep');
          }
        }
      }
    }
  }
}
''',
      [lint(0, 179)],
    );
  }
}

/// Exercises the test-DSL discount through the plugin path: the same
/// rule, but the unit lives at `…/test/lib/dsl_test.dart`, which
/// [TestAware.isTestPath] recognises as a conventional test file.
@reflectiveTest
class CognitiveComplexityRuleTestDslTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = CognitiveComplexityRule();
    super.setUp();
  }

  @override
  String get analysisRule => 'dartrics_cognitive_complexity';

  @override
  String get testFileName => 'dsl_test.dart';

  void test_dslCallbacks_doNotAccrueToMain_noLint() async {
    // Without the discount the if-ladder inside the two-closure stack
    // charges main() with (1+2)+(1+3)+(1+4)+(1+5)+(1+6) = 28 ≥ 15.
    await assertNoDiagnostics(r'''
void group(String name, void Function() body) {}
void test(String name, void Function() body) {}

void main() {
  group('g', () {
    test('a', () {
      if (1 > 0) {
        if (2 > 1) {
          if (3 > 2) {
            if (4 > 3) {
              if (5 > 4) {
                print('deep');
              }
            }
          }
        }
      }
    });
  });
}
''');
  }

  void test_ownControlFlow_stillLints() async {
    // The discount only exempts argument closures — a branchy named
    // helper in a test file keeps the production behavior.
    await assertDiagnostics(
      r'''
void f(int x) {
  if (x > 0) {
    if (x > 1) {
      if (x > 2) {
        if (x > 3) {
          if (x > 4) {
            print('deep');
          }
        }
      }
    }
  }
}
''',
      [lint(0, 179)],
    );
  }
}
