import 'ai_reporter.dart';
import 'console_reporter.dart';
import 'json_reporter.dart';
import 'md_reporter.dart';
import 'reporter.dart';
import 'sarif_reporter.dart';

/// Resolves the [Reporter] implementation for [name]. The CLI argument
/// parser restricts [name] to the known set, so this function relies on
/// `default → console` rather than a dead unreachable fallthrough.
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
    default:
      return ConsoleReporter();
  }
}
