import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartrics/src/metrics/metric_catalogue.dart'
    show collectRuleDescriptions;
import 'package:test/test.dart';

void main() {
  test(
    'config schema metrics.propertyNames.enum matches the runtime catalogue',
    () async {
      // Resolve the schema file via the package URI rather than
      // Directory.current — concurrent tests can chdir.
      final schemaFile = await _findSchemaFile();
      final schema =
          jsonDecode(schemaFile.readAsStringSync()) as Map<String, Object?>;
      // The schema's actual `dartrics:` shape lives in `$defs.Dartrics`
      // (the top-level `properties.dartrics` is a `$ref` into it). Walk
      // through that ref so the parity check stays robust to future
      // re-shaping of the top-level glue.
      final defs = (schema[r'$defs'] as Map<String, Object?>?) ?? const {};
      final dartricsBlock =
          (defs['Dartrics'] as Map<String, Object?>?) ?? const {};
      final properties =
          (dartricsBlock['properties'] as Map<String, Object?>?) ?? const {};
      final metrics = properties['metrics'] as Map<String, Object?>?;
      final propertyNames = metrics?['propertyNames'] as Map<String, Object?>?;
      final enumList =
          (propertyNames?['enum'] as List?)?.cast<String>().toSet() ??
          const <String>{};

      final runtimeIds = collectRuleDescriptions().map((r) => r.id).toSet();

      // The schema and the engine must list the exact same set of
      // metric ids. A drift here means either:
      //  - a new metric was added to the engine but not whitelisted in
      //    the schema (so users see false-positive validation errors),
      //  - or the schema lists a metric the engine no longer ships
      //    (so users get a stale autocomplete suggestion).
      // Fix by editing schemas/dartrics-config.schema.json.
      expect(enumList, equals(runtimeIds));
    },
  );
}

/// Locates the schema file relative to the *package root*, anchored on
/// the resolved location of `package:dartrics/src/metrics/metric_catalogue.dart`.
/// `Directory.current` is process-wide and another test (e.g.
/// `cli_flow_test`'s `runIn` extension) may have chdir'd into a temp
/// directory while running concurrently — the parent isolate sees that
/// changed cwd, so any cwd-relative path resolution flakes. Walking up
/// from a `package:` URI is immune to that.
Future<File> _findSchemaFile() async {
  final libUri = await Isolate.resolvePackageUri(
    Uri.parse('package:dartrics/src/metrics/metric_catalogue.dart'),
  );
  if (libUri == null) {
    fail(
      'Could not resolve package:dartrics/... — '
      'package_config.json missing?',
    );
  }
  // libUri points at <pkg>/lib/src/metrics/metric_catalogue.dart.
  // Walk up four parents: src/metrics → src → lib → <pkg>.
  final packageRoot = File.fromUri(libUri).parent.parent.parent.parent;
  final candidate = File(
    '${packageRoot.path}/schemas/dartrics-config.schema.json',
  );
  if (!candidate.existsSync()) {
    fail(
      'schemas/dartrics-config.schema.json not found at expected '
      'path ${candidate.path} (package root resolved to '
      '${packageRoot.path}).',
    );
  }
  return candidate;
}
