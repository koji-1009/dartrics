import 'package:args/command_runner.dart';

import 'ai_loop_command.dart';
import 'analyze_command.dart';
import 'doctor_command.dart';
import 'inspect_command.dart';
import 'manual_command.dart';
import 'regression_command.dart';
import 'report_command.dart';
import 'rules_command.dart';
import 'unused_command.dart';

CommandRunner<int> buildCommandRunner() {
  final runner = _DartricsRunner()
    ..argParser.addFlag(
      'version',
      negatable: false,
      help: 'Print the dartrics version and exit.',
    )
    ..addCommand(AnalyzeCommand())
    ..addCommand(UnusedCommand())
    ..addCommand(InspectCommand())
    ..addCommand(ReportCommand())
    ..addCommand(RulesCommand())
    ..addCommand(RegressionCommand())
    ..addCommand(ManualCommand())
    ..addCommand(AiLoopCommand())
    ..addCommand(DoctorCommand());
  return runner;
}

class _DartricsRunner extends CommandRunner<int> {
  _DartricsRunner()
    : super(
        'dartrics',
        'Dart code-quality metrics and unused public-API detection.',
      );

  @override
  String get usageFooter =>
      'AI agents: run `dartrics ai-loop` first — it prints the '
      'operational playbook (commands, prompts, dismiss syntax). '
      '`dartrics manual` is the conceptual reference.';
}
