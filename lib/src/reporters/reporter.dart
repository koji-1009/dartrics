import 'dart:io';

import '../models/analysis_report.dart';

abstract class Reporter {
  void report(AnalysisReport report, IOSink sink);
}
