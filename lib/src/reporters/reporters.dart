import 'ai_reporter.dart';
import 'console_reporter.dart';
import 'json_reporter.dart';
import 'md_reporter.dart';
import 'reporter.dart';
import 'sarif_reporter.dart';

/// Resolves the [Reporter] implementation for [name].
Reporter pickReporter(String name) {
  switch (name) {
    case 'json':
      return JsonReporter();
    case 'md':
      return MdReporter();
    case 'ai':
      return AiReporter();
    case 'sarif':
      return SarifReporter();
    case 'console':
      return ConsoleReporter();
  }
  return ConsoleReporter();
}
