import 'package:args/command_runner.dart';
import 'package:io/io.dart';

import 'common_options.dart';

/// `dartrics report` — re-emits a previously persisted JSON report in another
/// format. Phase 0 stub.
class ReportCommand extends Command<int> {
  ReportCommand() {
    addCommonOptions(argParser);
  }

  @override
  String get name => 'report';

  @override
  String get description =>
      'Re-emit a previously saved report in a different format.';

  @override
  Future<int> run() async {
    CommonOptions.from(this);
    return ExitCode.success.code;
  }
}
