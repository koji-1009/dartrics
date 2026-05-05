import 'console_reporter.dart';
import 'json_reporter.dart';
import 'reporter.dart';

/// Resolves the [Reporter] implementation for [name].
///
/// Phase 0 only ships `console` and `json`. `md`, `ai`, and `sarif` are wired
/// in Phase 5 and currently fall back to `console`.
Reporter pickReporter(String name) {
  switch (name) {
    case 'json':
      return JsonReporter();
    case 'console':
      return ConsoleReporter();
    case 'md':
    case 'ai':
    case 'sarif':
      return ConsoleReporter();
  }
  return ConsoleReporter();
}
