import 'package:args/command_runner.dart';
import 'package:io/io.dart';

import 'common_options.dart';

/// `dartrics unused` — runs only public-API reachability analysis.
///
/// Phase 0 stub: parses options and exits successfully. The detector is
/// implemented in Phase 4.
class UnusedCommand extends Command<int> {
  UnusedCommand() {
    addCommonOptions(argParser);
  }

  @override
  String get name => 'unused';

  @override
  String get description => 'Detect unreachable public declarations.';

  @override
  Future<int> run() async {
    CommonOptions.from(this);
    return ExitCode.success.code;
  }
}
