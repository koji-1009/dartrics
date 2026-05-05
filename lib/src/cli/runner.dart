import 'package:args/command_runner.dart';

import 'analyze_command.dart';
import 'report_command.dart';
import 'unused_command.dart';

CommandRunner<int> buildCommandRunner() {
  final runner = CommandRunner<int>(
    'dartrics',
    'Dart code-quality metrics and unused public-API detection.',
  )
    ..addCommand(AnalyzeCommand())
    ..addCommand(UnusedCommand())
    ..addCommand(ReportCommand());
  return runner;
}
