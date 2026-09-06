import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../config/config.dart';
import '../config/config_loader.dart';
import 'dismissal.dart';

/// Resolves the sidecar path for [config] against the analysis [root].
/// Lives here rather than on a command so every reader of the sidecar
/// (`analyze`, `doctor`) resolves it the same way.
String resolveDismissalsYamlPath(DismissalConfig config, String root) {
  final base = config.yamlPath ?? defaultDismissalsYamlPath;
  if (p.isAbsolute(base)) return base;
  return p.join(root, base);
}

/// Loads dismissal entries from a YAML sidecar at [path].
///
/// Returns an empty list (without raising) when the file is absent —
/// projects opt into the YAML channel via `analysis_options.yaml` but
/// might not have authored the sidecar yet. Structural problems
/// (`version`, `dismissals` list, missing required fields, malformed
/// `at:`) raise [ConfigException] which the CLI maps to `EX_CONFIG`.
///
/// Each entry's `file:` is resolved against [root] and normalised to an
/// absolute path. Absolute paths are the canonical form everywhere
/// downstream — [AnalyzerRunner] emits them, so `MetricRecord.file` and
/// the [DismissalIndex] key are absolute too. Without this step a
/// repo-relative `file:` (the form the manual documents) matches
/// nothing and is not even reported as stale.
List<Dismissal> loadYamlDismissals(String path, {required String root}) {
  final file = File(path);
  if (!file.existsSync()) return const [];
  final source = file.readAsStringSync();
  final YamlMap doc;
  try {
    final parsed = loadYaml(source);
    if (parsed is! YamlMap) {
      throw ConfigException('$path: top-level YAML must be a map');
    }
    doc = parsed;
  } on YamlException catch (e) {
    throw ConfigException('failed to parse $path: $e');
  }
  final version = doc['version'];
  if (version != 1) {
    throw ConfigException('$path: unsupported version "$version" (expected 1)');
  }
  final list = doc['dismissals'];
  if (list == null) return const [];
  if (list is! YamlList) {
    throw ConfigException('$path: `dismissals` must be a list');
  }
  final out = <Dismissal>[];
  for (var i = 0; i < list.length; i++) {
    final entry = list[i];
    if (entry is! YamlMap) {
      throw ConfigException(
        '$path: dismissals[$i] must be a map (got ${entry.runtimeType})',
      );
    }
    out.add(_parseEntry(entry, path: path, index: i, root: root));
  }
  return out;
}

Dismissal _parseEntry(
  YamlMap entry, {
  required String path,
  required int index,
  required String root,
}) {
  final reason = entry['reason'];
  final by = entry['by'];
  return Dismissal(
    file: _absoluteAgainst(
      _requireString(entry, 'file', path: path, index: index),
      root,
    ),
    scope: _requireString(entry, 'scope', path: path, index: index),
    metricId: _requireString(entry, 'metric', path: path, index: index),
    reason: reason is String ? reason : '',
    source: DismissalSource.yaml,
    by: by is String ? by : null,
    at: _parseAt(entry['at'], path: path, index: index),
  );
}

/// Normalises a sidecar `file:` value to the absolute, normalised form
/// the rest of the pipeline uses. [root] itself may be relative (the
/// CLI defaults `--root` to `.`), so it goes through `p.absolute` too.
String _absoluteAgainst(String file, String root) {
  if (p.isAbsolute(file)) return p.normalize(file);
  return p.normalize(p.absolute(p.join(root, file)));
}

String _requireString(
  YamlMap entry,
  String key, {
  required String path,
  required int index,
}) {
  final value = entry[key];
  if (value is! String) {
    throw ConfigException(
      '$path: dismissals[$index].$key is required and must be a string',
    );
  }
  return value;
}

/// `at:` is optional and accepts either a YAML-native timestamp scalar
/// (which `package:yaml` already decodes to [DateTime]) or an ISO-8601
/// string. Anything else is a `ConfigException`.
DateTime? _parseAt(Object? raw, {required String path, required int index}) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  if (raw is! String) {
    throw ConfigException(
      '$path: dismissals[$index].at must be a string or timestamp '
      '(got ${raw.runtimeType})',
    );
  }
  try {
    return DateTime.parse(raw);
  } on FormatException catch (e) {
    throw ConfigException(
      '$path: dismissals[$index].at is not a valid ISO-8601 timestamp '
      '($raw): ${e.message}',
    );
  }
}
