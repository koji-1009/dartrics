// `analyzer_testing` requires snake_case `test_*` instance methods, which
// trip the project's strict naming and avoid_void_async lints.
// ignore_for_file: non_constant_identifier_names, avoid_void_async

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:dartrics/src/lint/rules/number_of_parameters_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(NumberOfParametersRuleTest);
  });
}

@reflectiveTest
class NumberOfParametersRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = NumberOfParametersRule();
    super.setUp();
  }

  @override
  String get analysisRule => 'dartrics_number_of_parameters';

  void test_threeParams_noLint() async {
    await assertNoDiagnostics(r'''
int f(int a, int b, int c) => a;
''');
  }

  void test_fourParams_lint() async {
    await assertDiagnostics(
      r'''
int f(int a, int b, int c, int d) => a;
''',
      [lint(0, 39)],
    );
  }

  void test_methodWithFiveParams_lint() async {
    await assertDiagnostics(
      r'''
class C {
  void m(int a, int b, int c, int d, int e) {}
}
''',
      [lint(12, 44)],
    );
  }

  void test_constructorWithFiveParams_lint() async {
    await assertDiagnostics(
      r'''
class C {
  C(int a, int b, int c, int d, int e) {
    print(a + b + c + d + e);
  }
}
''',
      [lint(12, 72)],
    );
  }
}
