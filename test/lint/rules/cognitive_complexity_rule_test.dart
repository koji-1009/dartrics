// `analyzer_testing` requires snake_case `test_*` instance methods, which
// trip the project's strict naming and avoid_void_async lints.
// ignore_for_file: non_constant_identifier_names, avoid_void_async

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:dartrics/src/lint/rules/cognitive_complexity_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(CognitiveComplexityRuleTest);
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
