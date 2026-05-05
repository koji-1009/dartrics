import 'package:dartrics/src/lint/lint_options.dart';
import 'package:test/test.dart';

void main() {
  test('parse returns defaults when content is empty', () {
    final opt = LintOptions.parse('');
    expect(opt.warningThresholdById, isEmpty);
    expect(opt.thresholdFor('cyclomatic-complexity', 10), 10);
  });

  test('parse returns defaults when YAML root is not a map', () {
    final opt = LintOptions.parse('"just a string"\n');
    expect(opt.warningThresholdById, isEmpty);
  });

  test('parse returns defaults when no `dartrics:` section is present', () {
    final opt = LintOptions.parse('analyzer:\n  exclude: []\n');
    expect(opt.warningThresholdById, isEmpty);
  });

  test('parse returns defaults when no `metrics:` sub-section is present', () {
    final opt = LintOptions.parse(
      'dartrics:\n  unused:\n    entry-points:\n      - main\n',
    );
    expect(opt.warningThresholdById, isEmpty);
  });

  test('parse picks up the `warning:` field for each metric', () {
    final opt = LintOptions.parse('''
dartrics:
  metrics:
    cyclomatic-complexity:
      warning: 5
      error: 20
    cognitive-complexity:
      warning: 12
''');
    expect(opt.warningThresholdById['cyclomatic-complexity'], 5);
    expect(opt.warningThresholdById['cognitive-complexity'], 12);
  });

  test('parse accepts the bare-integer short form as a warning threshold', () {
    final opt = LintOptions.parse('''
dartrics:
  metrics:
    number-of-parameters: 6
''');
    expect(opt.warningThresholdById['number-of-parameters'], 6);
  });

  test('parse skips entries with no `warning:` and no scalar value', () {
    final opt = LintOptions.parse('''
dartrics:
  metrics:
    cyclomatic-complexity:
      error: 20
    cognitive-complexity:
      warning: 8
''');
    expect(
      opt.warningThresholdById.containsKey('cyclomatic-complexity'),
      isFalse,
    );
    expect(opt.warningThresholdById['cognitive-complexity'], 8);
  });

  test('parse falls back to defaults on malformed YAML', () {
    final opt = LintOptions.parse('dartrics:\n  metrics:\n    {broken\n');
    expect(opt.warningThresholdById, isEmpty);
  });

  test(
    'thresholdFor returns the override when present, fallback otherwise',
    () {
      const opt = LintOptions(
        warningThresholdById: {'cyclomatic-complexity': 5},
      );
      expect(opt.thresholdFor('cyclomatic-complexity', 10), 5);
      expect(opt.thresholdFor('cognitive-complexity', 15), 15);
    },
  );
}
