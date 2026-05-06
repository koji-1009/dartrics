import 'ai_reporter.dart';
import 'console_reporter.dart';
import 'json_reporter.dart';
import 'md_reporter.dart';
import 'reporter.dart';
import 'sarif_reporter.dart';

/// Resolves the [Reporter] implementation for [name]. The CLI argument
/// parser restricts [name] to the known set, so this function relies on
/// `default → console` rather than a dead unreachable fallthrough.
///
/// [limit] caps the violations and unused entries shown by the AI and
/// markdown reporters. `null` (the default) keeps every entry.
/// JSON / SARIF / console always emit the full set — downstream
/// pipelines do their own filtering.
Reporter pickReporter(String name, {int? limit}) {
  switch (name) {
    case 'json':
      return JsonReporter();
    case 'md':
      return MdReporter(limit: limit);
    case 'ai':
      return AiReporter(limit: limit);
    case 'sarif':
      return SarifReporter();
    default:
      return ConsoleReporter();
  }
}
