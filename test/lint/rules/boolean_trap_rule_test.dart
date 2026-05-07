// `analyzer_testing` requires snake_case `test_*` instance methods, which
// trip the project's strict naming and avoid_void_async lints.
// ignore_for_file: non_constant_identifier_names, avoid_void_async

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:dartrics/src/lint/rules/boolean_trap_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(BooleanTrapRuleTest);
  });
}

@reflectiveTest
class BooleanTrapRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = BooleanTrapRule();
    super.setUp();
  }

  @override
  String get analysisRule => 'dartrics_boolean_trap';

  void test_singleBoolParam_noLint() async {
    await assertNoDiagnostics(r'''
void show(bool visible) {}
''');
  }

  void test_zeroBoolParams_noLint() async {
    await assertNoDiagnostics(r'''
int add(int a, int b) => a + b;
''');
  }

  void test_twoBoolParams_lint() async {
    await assertDiagnostics(
      r'''
void apply(bool show, bool selected) {}
''',
      [lint(0, 39)],
    );
  }

  void test_namedBoolParams_noLint() async {
    // Named bool parameters are self-documenting at the call site
    // and intentionally not counted toward the boolean-trap signal.
    await assertNoDiagnostics(r'''
void apply({required bool a, required bool b, bool c = false}) {}
''');
  }

  void test_mixedSignature_countsPositionalOnly() async {
    // Two positional + one named = 2 positional, threshold is 2.
    await assertDiagnostics(
      r'''
void apply(bool show, bool selected, {required bool flush}) {}
''',
      [lint(0, 62)],
    );
  }

  void test_thisDotConstructorParam_skipped() async {
    // `this.x` parameters carry their type on the field, not the
    // signature. The boolean-trap antipattern is about call-site
    // ambiguity, which `this.x` doesn't create.
    await assertNoDiagnostics(r'''
class Widget {
  final bool visible;
  final bool selected;
  Widget(this.visible, this.selected);
}
''');
  }
}
