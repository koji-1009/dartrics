// `analyzer_testing` requires snake_case `test_*` instance methods, which
// trip the project's strict naming and avoid_void_async lints.
// ignore_for_file: non_constant_identifier_names, avoid_void_async

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:dartrics/src/lint/rules/cyclomatic_complexity_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(CyclomaticComplexityRuleTest);
  });
}

@reflectiveTest
class CyclomaticComplexityRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = CyclomaticComplexityRule();
    super.setUp();
  }

  @override
  String get analysisRule => 'dartrics_cyclomatic_complexity';

  void test_simpleFunction_noLint() async {
    await assertNoDiagnostics(r'''
int add(int a, int b) => a + b;
''');
  }

  void test_atThreshold_lint() async {
    // CC reaches 10 (1 base + 9 ifs); the lint highlights the whole function
    // declaration.
    await assertDiagnostics(
      r'''
int rate(int x) {
  if (x == 0) return 0;
  if (x == 1) return 1;
  if (x == 2) return 2;
  if (x == 3) return 3;
  if (x == 4) return 4;
  if (x == 5) return 5;
  if (x == 6) return 6;
  if (x == 7) return 7;
  if (x == 8) return 8;
  return -1;
}
''',
      [lint(0, 248)],
    );
  }
}
