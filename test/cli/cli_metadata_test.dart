import 'package:dartrics/src/cli/runner.dart';
import 'package:test/test.dart';

void main() {
  test('every subcommand exposes a non-empty description', () {
    final runner = buildCommandRunner();
    expect(runner.commands['analyze']!.description, isNotEmpty);
    expect(runner.commands['unused']!.description, isNotEmpty);
    expect(runner.commands['report']!.description, isNotEmpty);
    expect(runner.commands['rules']!.description, isNotEmpty);
  });

  test('top-level help footer points AI agents at ai-loop first', () {
    final usage = buildCommandRunner().usage;
    expect(usage, contains('AI agents: run `dartrics ai-loop` first'));
  });
}
