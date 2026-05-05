import 'package:dartrics/src/cli/runner.dart';
import 'package:test/test.dart';

void main() {
  test('every subcommand exposes a non-empty description', () {
    final runner = buildCommandRunner();
    expect(runner.commands['analyze']!.description, isNotEmpty);
    expect(runner.commands['unused']!.description, isNotEmpty);
    expect(runner.commands['report']!.description, isNotEmpty);
  });
}
