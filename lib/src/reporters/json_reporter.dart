import 'dart:convert';
import 'dart:io';

import '../models/analysis_report.dart';
import 'reporter.dart';

/// Stable-schema JSON output suitable for `jq`, SARIF transformation, and
/// programmatic ingestion.
class JsonReporter implements Reporter {
  @override
  void report(AnalysisReport report, IOSink sink) {
    const encoder = JsonEncoder.withIndent('  ');
    sink.writeln(encoder.convert(report.toJson()));
  }
}
