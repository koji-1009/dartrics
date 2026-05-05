import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dartrics/dartrics.dart';
import 'package:test/test.dart';

void main() {
  test('reports cyclomatic-complexity violation when threshold exceeded', () {
    const source = '''
int rate(int x) {
  if (x > 0) {
    if (x > 10) return 3;
    return 2;
  }
  if (x < 0) return -1;
  return 0;
}
''';
    final result = parseString(content: source);
    final diagnostics = diagnose(
      unit: result.unit,
      lineInfo: result.lineInfo,
      path: 'r.dart',
      source: source,
      config: const DartricsLintConfig(
        cyclomaticComplexity: RuleConfig(enabled: true, warning: 2),
      ),
    );
    expect(
      diagnostics.any(
        (d) =>
            d.ruleId == 'cyclomatic-complexity' &&
            d.severity == DiagnosticSeverity.warning,
      ),
      isTrue,
    );
  });

  test('disabled rule does not emit diagnostics', () {
    const source = 'int f() { if (true) return 1; return 0; }';
    final result = parseString(content: source);
    final diagnostics = diagnose(
      unit: result.unit,
      lineInfo: result.lineInfo,
      path: 'r.dart',
      source: source,
      config: const DartricsLintConfig(
        cyclomaticComplexity: RuleConfig(enabled: false, warning: 1),
      ),
    );
    expect(
      diagnostics.where((d) => d.ruleId == 'cyclomatic-complexity'),
      isEmpty,
    );
  });

  test('number-of-parameters > 8 produces error severity', () {
    const source =
        'int f(int a, int b, int c, int d, int e, int g, int h, int i, int j) => 0;';
    final result = parseString(content: source);
    final diagnostics = diagnose(
      unit: result.unit,
      lineInfo: result.lineInfo,
      path: 'r.dart',
      source: source,
    );
    final paramD = diagnostics
        .where((d) => d.ruleId == 'number-of-parameters')
        .toList();
    expect(paramD, hasLength(1));
    expect(paramD.first.severity, DiagnosticSeverity.error);
  });

  test('class methods and constructors are visited as separate scopes', () {
    const source = '''
class C {
  C() {
    if (true) {
      if (true) {
        if (true) {
          if (true) {
            if (true) print('a');
          }
        }
      }
    }
  }
  void m(int a, int b, int c, int d, int e) {}
}
''';
    final result = parseString(content: source);
    final diagnostics = diagnose(
      unit: result.unit,
      lineInfo: result.lineInfo,
      path: 'r.dart',
      source: source,
      // Lower the parameter warning so the 5-arg method definitely triggers
      // even if the default ever drifts.
      config: const DartricsLintConfig(
        numberOfParameters: RuleConfig(enabled: true, warning: 4),
      ),
    );
    // The constructor's 5-deep nested ifs trip max-nesting (default warn=4);
    // the method's 5-parameter signature trips number-of-parameters.
    expect(
      diagnostics.where((d) => d.ruleId == 'maximum-nesting-level'),
      isNotEmpty,
    );
    expect(
      diagnostics.where((d) => d.ruleId == 'number-of-parameters'),
      isNotEmpty,
    );
  });
}
