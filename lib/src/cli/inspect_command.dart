import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart';

import '../analyzer_runner.dart';
import '../config/config_loader.dart';
import '../models/call_graph_inspection.dart';
import '../unused/resolved_reachability.dart';
import 'common_options.dart';
import 'io_sinks.dart';

/// Allowed values for `--reporter` on `inspect`. The full set of report
/// formats does not apply here (e.g. `sarif` and `md` summarise
/// findings, which the inspector does not produce); JSON and the
/// YAML-ish AI shape cover the two consumer paths.
const _inspectReporters = ['ai', 'json'];

/// `dartrics inspect <symbol>` — walks the resolved call graph around
/// a named declaration and prints the upstream / downstream
/// neighbourhood.
class InspectCommand extends Command<int> {
  InspectCommand() {
    addIoOptions(
      argParser,
      reporters: _inspectReporters,
      defaultReporter: 'ai',
    );
    addAnalysisOptions(argParser);
    argParser
      ..addOption(
        'depth',
        help:
            'Maximum number of edges from the anchor declaration. '
            'Default 2.',
        defaultsTo: '2',
      )
      ..addOption(
        'direction',
        help:
            'Side(s) of the graph to walk. `up` returns callers only, '
            '`down` returns callees only, `both` (default) returns the '
            'union.',
        allowed: ['up', 'down', 'both'],
        defaultsTo: 'both',
      );
  }

  @override
  String get name => 'inspect';

  @override
  String get description =>
      'Walk the resolved call graph around a named declaration.';

  @override
  String get invocation =>
      'dartrics inspect <symbol> [--depth N] [--direction up|down|both]';

  @override
  Future<int> run() async {
    final io = IoOptions.from(this);
    final analysis = AnalysisOptions.from(this);
    final rest = io.rest;
    if (rest.length != 1) {
      DartricsIO.stderrSink.writeln(
        'inspect: pass exactly one symbol name (got ${rest.length})',
      );
      DartricsIO.stderrSink.writeln(invocation);
      return ExitCode.usage.code;
    }
    final symbol = rest.single;
    final int depth;
    try {
      depth = _parsePositiveInt(argResults!['depth'] as String, 'depth');
    } on FormatException catch (e) {
      DartricsIO.stderrSink.writeln('dartrics inspect: ${e.message}');
      return ExitCode.usage.code;
    }
    // `--direction` is constrained by `argParser.allowed`, so the
    // `byName` lookup is total against the supplied value — no need
    // for an explicit fallback / throw.
    final direction = InspectionDirection.values.byName(
      argResults!['direction'] as String,
    );

    // Load the config so that root / since options behave the same way
    // they do on `analyze`. We do not use the config beyond root /
    // analyzer concurrency; metric and dismissal settings have no
    // bearing on the call graph.
    await loadConfig(analysis.configPath);
    final runner = AnalyzerRunner(
      roots: [analysis.root],
      concurrency: analysis.concurrency,
    );
    final units = await runner.resolveAll();
    final result = inspectCallGraph(
      [for (final u in units) (path: u.path, unit: u.unit)],
      query: symbol,
      depth: depth,
      direction: direction,
    );
    final IOSink sink;
    final bool ownsSink;
    if (io.output == '-') {
      sink = DartricsIO.stdoutSink;
      ownsSink = false;
    } else {
      sink = File(io.output).openWrite();
      ownsSink = true;
    }
    try {
      switch (io.reporter) {
        case 'json':
          _emitJson(result, sink);
        case 'ai':
        default:
          _emitAi(result, sink);
      }
    } finally {
      if (ownsSink) await sink.close();
    }
    return ExitCode.success.code;
  }
}

int _parsePositiveInt(String raw, String name) {
  final n = int.tryParse(raw);
  if (n == null || n < 1) {
    throw FormatException('--$name must be a positive integer (got "$raw")');
  }
  return n;
}

void _emitJson(InspectionResult result, IOSink sink) {
  const encoder = JsonEncoder.withIndent('  ');
  sink.writeln(encoder.convert(result.toJson()));
}

void _emitAi(InspectionResult result, IOSink sink) {
  sink
    ..writeln('# dartrics inspect-report v1')
    ..writeln(
      '# Subgraph of the resolved call graph around the queried symbol.',
    )
    ..writeln(
      '# Values are reference information — compare against intent, not '
      'against a threshold.',
    )
    ..writeln('query: ${result.query}')
    ..writeln('depth: ${result.depth}')
    ..writeln('direction: ${result.direction.name}');
  if (result.matches.isEmpty) {
    sink.writeln('matches: []');
    return;
  }
  sink.writeln('matches:');
  for (final match in result.matches) {
    sink
      ..writeln('  - anchor:')
      ..writeln('      file: ${match.anchor.file}')
      ..writeln('      line: ${match.anchor.scope.location.line}')
      ..writeln('      scope: ${match.anchor.scope.name}')
      ..writeln('      kind: ${match.anchor.scope.kind.name}')
      ..writeln('      fanInCallers: ${match.anchor.fanInCallers}')
      ..writeln('      fanInCalls: ${match.anchor.fanInCalls}')
      ..writeln('      fanOutCallees: ${match.anchor.fanOutCallees}')
      ..writeln('      fanOutCalls: ${match.anchor.fanOutCalls}');
    _emitAiNodes(sink, 'upstream', match.upstream);
    _emitAiNodes(sink, 'downstream', match.downstream);
  }
}

void _emitAiNodes(IOSink sink, String key, List<InspectionNode> nodes) {
  if (nodes.isEmpty) {
    sink.writeln('    $key: []');
    return;
  }
  sink.writeln('    $key:');
  for (final n in nodes) {
    sink
      ..writeln('      - depth: ${n.depth}')
      ..writeln('        incomingEdgeCount: ${n.incomingEdgeCount}')
      ..writeln('        file: ${n.signal.file}')
      ..writeln('        line: ${n.signal.scope.location.line}')
      ..writeln('        scope: ${n.signal.scope.name}')
      ..writeln('        kind: ${n.signal.scope.kind.name}')
      ..writeln('        fanInCallers: ${n.signal.fanInCallers}')
      ..writeln('        fanInCalls: ${n.signal.fanInCalls}')
      ..writeln('        fanOutCallees: ${n.signal.fanOutCallees}')
      ..writeln('        fanOutCalls: ${n.signal.fanOutCalls}');
  }
}
