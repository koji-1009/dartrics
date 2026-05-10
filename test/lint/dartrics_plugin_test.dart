import 'package:analysis_server_plugin/registry.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:dartrics/src/lint/dartrics_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('plugin name matches the analysis_options.yaml plugins: key', () {
    expect(DartricsPlugin().name, 'dartrics');
  });

  test('register() wires every rule as a default-on warning', () {
    final registry = _RecordingRegistry();
    DartricsPlugin().register(registry);
    expect(
      registry.warningRuleNames,
      containsAll([
        'dartrics_cyclomatic_complexity',
        'dartrics_cognitive_complexity',
        'dartrics_number_of_parameters',
      ]),
    );
    expect(
      registry.lintRuleNames,
      isEmpty,
      reason: 'all rules ship as default-on warnings, not opt-in lints',
    );
  });
}

/// Minimal `PluginRegistry` stand-in. Implements only the two `register*`
/// methods the plugin actually exercises; other members fall through
/// `noSuchMethod` since the test does not invoke them.
class _RecordingRegistry implements PluginRegistry {
  final warningRuleNames = <String>[];
  final lintRuleNames = <String>[];

  @override
  void registerWarningRule(AbstractAnalysisRule rule) {
    warningRuleNames.add(rule.name);
  }

  @override
  void registerLintRule(AbstractAnalysisRule rule) {
    lintRuleNames.add(rule.name);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
