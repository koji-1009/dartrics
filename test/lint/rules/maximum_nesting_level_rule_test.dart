// `analyzer_testing` requires snake_case `test_*` instance methods, which
// trip the project's strict naming and avoid_void_async lints.
// ignore_for_file: non_constant_identifier_names, avoid_void_async

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:dartrics/src/lint/rules/maximum_nesting_level_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(MaximumNestingLevelRuleTest);
  });
}

@reflectiveTest
class MaximumNestingLevelRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = MaximumNestingLevelRule();
    super.setUp();
  }

  @override
  String get analysisRule => 'dartrics_maximum_nesting_level';

  void test_flatFunction_noLint() async {
    await assertNoDiagnostics(r'''
int f(int x) {
  if (x > 0) return 1;
  return 0;
}
''');
  }

  void test_atThreshold_lint() async {
    // Four-deep nesting trips the warning.
    await assertDiagnostics(
      r'''
void f(int x) {
  if (x > 0) {
    if (x > 1) {
      if (x > 2) {
        if (x > 3) {
          print('deep');
        }
      }
    }
  }
}
''',
      [lint(0, 142)],
    );
  }
}
