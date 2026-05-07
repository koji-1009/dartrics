import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart';

import 'io_sinks.dart';
import 'manual_text.dart';

/// `dartrics manual` — prints the operator's manual for AI consumers.
///
/// The manual frames each metric as a lens on a specific kind of "hard to
/// read" and spells out the accept / refactor / dismiss decision step that
/// distinguishes dartrics from a linter. AI agents (Claude Code, Cursor,
/// Codex, Aider, OpenHands, …) running dartrics as part of a self-review
/// loop are the primary audience; the same content lives in
/// `doc/manual.md` for human reading on github / pub.dev.
///
/// Output is the markdown source verbatim. Markdown is the lingua franca
/// of LLM-tool harnesses, and most terminals render the headings / fences
/// readably enough for human spot-checks.
class ManualCommand extends Command<int> {
  ManualCommand() {
    argParser.addOption(
      'output',
      help: 'Output destination. Use "-" for stdout.',
      defaultsTo: '-',
    );
  }

  @override
  String get name => 'manual';

  @override
  String get description =>
      "Print the dartrics operator's manual for AI agents.";

  @override
  Future<int> run() async {
    final output = argResults!['output'] as String;
    if (output == '-') {
      DartricsIO.stdoutSink.write(manualText);
    } else {
      final sink = File(output).openWrite();
      try {
        sink.write(manualText);
      } finally {
        await sink.close();
      }
    }
    return ExitCode.success.code;
  }
}
