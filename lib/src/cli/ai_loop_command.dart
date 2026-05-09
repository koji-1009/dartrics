import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart';

import 'ai_loop_text.dart';
import 'io_sinks.dart';

/// `dartrics ai-loop` — prints the four-station walkthrough that drives
/// dartrics inside an AI refactor loop (setup / propose / apply / verify).
///
/// Pairs with `dartrics manual` (the lens reference) and `dartrics rules`
/// (the metric catalogue): an agent that has just installed dartrics can
/// `dartrics ai-loop | claude -p "..."` to learn the contract without
/// reaching out to the network. The same content lives in
/// `doc/ai-loop.md` for human reading on github / pub.dev.
class AiLoopCommand extends Command<int> {
  AiLoopCommand() {
    argParser.addOption(
      'output',
      help: 'Output destination. Use "-" for stdout.',
      defaultsTo: '-',
    );
  }

  @override
  String get name => 'ai-loop';

  @override
  String get description =>
      'Print the AI-loop walkthrough (setup / propose / apply / verify).';

  @override
  Future<int> run() async {
    final output = argResults!['output'] as String;
    if (output == '-') {
      DartricsIO.stdoutSink.write(aiLoopText);
    } else {
      final sink = File(output).openWrite();
      try {
        sink.write(aiLoopText);
      } finally {
        await sink.close();
      }
    }
    return ExitCode.success.code;
  }
}
