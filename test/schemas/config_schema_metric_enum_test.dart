import 'dart:convert';
import 'dart:io';

import 'package:dartrics/src/metrics/metric_catalogue.dart'
    show collectRuleDescriptions;
import 'package:test/test.dart';

void main() {
  test(
    'config schema metrics.propertyNames.enum matches the runtime catalogue',
    () {
      // Walk up to the repo root to find the schema file. Tests can run
      // from cwd or a workspace package; both paths should resolve.
      final schemaFile = _findSchemaFile();
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

File _findSchemaFile() {
  Directory dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final candidate = File('${dir.path}/schemas/dartrics-config.schema.json');
    if (candidate.existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail(
    'schemas/dartrics-config.schema.json not found from '
    '${Directory.current.path}',
  );
}
