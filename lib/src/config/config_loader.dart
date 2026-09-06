import 'dart:io';

import 'package:io/io.dart';
import 'package:logging/logging.dart';
import 'package:yaml/yaml.dart';

import '../metrics/metric_catalogue.dart' show defaultMetricThresholds;
import '../unused/keep_alive_presets.dart' show conventionRootPresets;
import 'config.dart';

final _log = Logger('config_loader');

/// Loads dartrics configuration from [path]. Falls back to defaults when the
/// file is missing or has no `dartrics:` section. Throws [_ConfigException]
/// (caller should surface as `EX_CONFIG`) for malformed content.
Future<Config> loadConfig(String path) async {
  final file = File(path);
  if (!file.existsSync()) {
    _log.fine('config file $path not found, using defaults');
    return _defaultConfig();
  }
  final source = await file.readAsString();
  final YamlMap root;
  try {
    final parsed = loadYaml(source);
    if (parsed is! YamlMap) {
      return _defaultConfig();
    }
    root = parsed;
  } on YamlException catch (e) {
    throw ConfigException('failed to parse $path: $e');
  }

  final dartrics = root['dartrics'];
  if (dartrics is! YamlMap) {
    return _defaultConfig();
  }

  return Config(
    metricThresholds: _parseMetrics(dartrics['metrics']),
    unused: _parseUnused(dartrics['unused']),
    exclude: _parseStringList(dartrics['exclude']),
    flutter: dartrics['flutter'] as bool? ?? true,
    test: dartrics['test'] as bool? ?? true,
    snapshot: _parseSnapshot(dartrics['snapshot']),
    dismissals: _parseDismissals(dartrics['dismissals']),
    unknownKeys: collectUnknownConfigKeys(dartrics),
  );
}

/// Keys the loader honours per config-map path. Mirrors
/// `schemas/dartrics-config.schema.json` (`additionalProperties: false`
/// at every level); `dartrics doctor` uses the same table for its
/// did-you-mean hints so the loader and the diagnosis cannot drift.
/// `dartrics.metrics.<id>` maps are keyed by user-chosen ids and are
/// handled structurally in [collectUnknownConfigKeys] instead.
const Map<String, Set<String>> knownConfigKeys = {
  'dartrics': {
    'metrics',
    'unused',
    'exclude',
    'flutter',
    'test',
    'snapshot',
    'dismissals',
  },
  'dartrics.unused': {
    'entry-points',
    'exclude-exported',
    'ignore-annotations',
    'roots',
    'filter',
  },
  'dartrics.dismissals': {
    'sources',
    'requireReason',
    'minReasonLength',
    'requireAuthor',
    'requireTimestamp',
    'warnStale',
    'yamlPath',
  },
  'dartrics.dismissals.sources': {'comment', 'yaml'},
  'dartrics.snapshot': {'mode', 'path'},
};

/// Fields accepted inside each `dartrics.metrics.<id>:` map.
const Set<String> knownMetricOptionKeys = {'enabled', 'warning', 'error'};

/// Walks the `dartrics:` map and returns the dotted path of every key
/// the loader would silently ignore. Parsing stays lenient — unknown
/// keys never fail a run — but the list rides on [Config.unknownKeys]
/// so `dartrics doctor` can surface them.
List<String> collectUnknownConfigKeys(YamlMap dartrics) => [
  ..._unknownKeysIn(dartrics, 'dartrics'),
  ..._unknownMetricOptionKeys(dartrics['metrics']),
  ..._unknownNestedKeys(dartrics),
];

/// Keys of [map] not accepted at config path [prefix], as dotted paths.
/// Paths absent from [knownConfigKeys] are the id-keyed
/// `dartrics.metrics.<id>` maps, which share [knownMetricOptionKeys].
Iterable<String> _unknownKeysIn(YamlMap map, String prefix) {
  final known = knownConfigKeys[prefix] ?? knownMetricOptionKeys;
  return map.keys
      .map((key) => key.toString())
      .where((name) => !known.contains(name))
      .map((name) => '$prefix.$name');
}

Iterable<String> _unknownMetricOptionKeys(Object? metrics) sync* {
  if (metrics is! YamlMap) return;
  for (final entry in metrics.entries) {
    final value = entry.value;
    if (value is YamlMap) {
      yield* _unknownKeysIn(value, 'dartrics.metrics.${entry.key}');
    }
  }
}

Iterable<String> _unknownNestedKeys(YamlMap dartrics) sync* {
  for (final path in knownConfigKeys.keys) {
    if (path == 'dartrics') continue;
    final node = _nodeAt(dartrics, path);
    if (node is YamlMap) {
      yield* _unknownKeysIn(node, path);
    }
  }
}

/// Resolves the node at dotted [path] (relative to the `dartrics:`
/// map, whose own segment is skipped), or `null` when any intermediate
/// node is missing or not a map.
Object? _nodeAt(YamlMap dartrics, String path) {
  Object? node = dartrics;
  for (final segment in path.split('.').skip(1)) {
    node = node is YamlMap ? node[segment] : null;
  }
  return node;
}

DismissalConfig _parseDismissals(Object? node) {
  if (node == null) return const DismissalConfig();
  if (node is! YamlMap) {
    throw ConfigException(
      'dartrics.dismissals must be a map (got ${node.runtimeType})',
    );
  }
  final (:comment, :yamlSource) = _parseDismissalSources(node['sources']);
  if (!comment && !yamlSource) {
    throw ConfigException(
      'dartrics.dismissals: at least one dismissal source must be enabled',
    );
  }
  final minReasonLength = _parseMinReasonLength(node['minReasonLength']);
  final requireAuthor = _parseGatedBool(
    node['requireAuthor'],
    yamlSource: yamlSource,
    key: 'requireAuthor',
  );
  final requireTimestamp = _parseGatedBool(
    node['requireTimestamp'],
    yamlSource: yamlSource,
    key: 'requireTimestamp',
  );
  final yamlPath = node['yamlPath'];
  return DismissalConfig(
    commentSource: comment,
    yamlSource: yamlSource,
    requireReason: node['requireReason'] as bool? ?? true,
    minReasonLength: minReasonLength,
    requireAuthor: requireAuthor,
    requireTimestamp: requireTimestamp,
    warnStale: node['warnStale'] as bool? ?? true,
    yamlPath: yamlPath is String ? yamlPath : null,
  );
}

/// Resolves the `sources:` sub-block. Three shapes:
///
/// - absent → both channels on (bare `dismissals:` is the AI-friendly
///   default so the user does not have to enumerate them)
/// - YamlMap with explicit `comment` / `yaml` keys → user override
/// - anything else → `ConfigException`
({bool comment, bool yamlSource}) _parseDismissalSources(Object? node) {
  if (node == null) return (comment: true, yamlSource: true);
  if (node is! YamlMap) {
    throw ConfigException(
      'dartrics.dismissals.sources must be a map (got ${node.runtimeType})',
    );
  }
  return (
    comment: node['comment'] as bool? ?? true,
    yamlSource: node['yaml'] as bool? ?? true,
  );
}

int _parseMinReasonLength(Object? raw) {
  final value = raw is int ? raw : defaultDismissalMinReasonLength;
  if (value < 0) {
    throw ConfigException(
      'dartrics.dismissals.minReasonLength must be non-negative',
    );
  }
  return value;
}

/// Parses a `bool` knob that is only meaningful when the YAML source
/// is enabled (the carried metadata field lives on YAML entries, not
/// on `// dartrics:dismiss` comments). [key] is interpolated into the
/// error message to keep both call-site error messages identical.
bool _parseGatedBool(
  Object? raw, {
  required bool yamlSource,
  required String key,
}) {
  final value = raw as bool? ?? false;
  if (value && !yamlSource) {
    throw ConfigException('dartrics.dismissals.$key needs sources.yaml: true');
  }
  return value;
}

SnapshotConfig _parseSnapshot(Object? node) {
  if (node is String) {
    return SnapshotConfig(mode: _modeFromString(node));
  }
  if (node is YamlMap) {
    final modeRaw = node['mode'];
    final mode = modeRaw is String
        ? _modeFromString(modeRaw)
        : SnapshotMode.cache;
    final path = node['path'];
    return SnapshotConfig(mode: mode, path: path is String ? path : null);
  }
  if (node is bool) {
    return SnapshotConfig(mode: node ? .cache : .none);
  }
  return const SnapshotConfig();
}

SnapshotMode _modeFromString(String raw) => switch (raw) {
  'cache' => .cache,
  'baseline' => .baseline,
  'none' || 'off' => .none,
  _ => throw ConfigException(
    'unknown snapshot mode "$raw" (expected cache | baseline | none)',
  ),
};

Map<String, MetricThresholds> _parseMetrics(Object? node) {
  // Start from the built-in default thresholds so the CLI fires
  // violations on a default-config project the same way the analyzer
  // plugin does. User-supplied entries override individual fields
  // (`enabled` / `warning` / `error`) per metric; metrics absent from
  // the user block keep their built-in warning so a freshly-installed
  // dartrics is useful without a `dartrics:` block at all.
  final map = <String, MetricThresholds>{
    for (final e in defaultMetricThresholds.entries)
      e.key: MetricThresholds(warning: e.value),
  };
  if (node is! YamlMap) return map;
  for (final entry in node.entries) {
    final id = entry.key.toString();
    final user = _thresholdsFromYaml(entry.value);
    if (user == null) continue;
    final base = map[id];
    if (base == null) {
      map[id] = user;
    } else {
      // Per-field merge: a YAML override that omits `warning` keeps the
      // built-in default rather than silently falling back to "no
      // threshold". `error` has no built-in default — only user-set
      // values reach the engine.
      map[id] = MetricThresholds(
        enabled: user.enabled,
        warning: user.warning ?? base.warning,
        error: user.error,
      );
    }
  }
  return map;
}

MetricThresholds? _thresholdsFromYaml(Object? value) {
  if (value is YamlMap) {
    return MetricThresholds(
      enabled: value['enabled'] as bool?,
      warning: _asNum(value['warning']),
      error: _asNum(value['error']),
    );
  }
  if (value is num) return MetricThresholds(warning: value);
  if (value is bool) return MetricThresholds(enabled: value);
  return null;
}

UnusedConfig _parseUnused(Object? node) {
  if (node is! YamlMap) return const UnusedConfig();
  return UnusedConfig(
    entryPoints: _parseStringList(
      node['entry-points'],
      fallback: const ['main', '@pragma:vm:entry-point', 'test'],
    ),
    excludeExported: node['exclude-exported'] as bool? ?? true,
    ignoreAnnotations: _parseStringList(
      node['ignore-annotations'],
      fallback: const ['visibleForTesting', 'protected', 'JsonSerializable'],
    ),
    roots: _parseStringList(node['roots'], fallback: conventionRootPresets),
    filter: _parseStringList(node['filter']),
  );
}

List<String> _parseStringList(
  Object? node, {
  List<String> fallback = const [],
}) {
  if (node is YamlList) {
    return node.map((e) => e.toString()).toList(growable: false);
  }
  return fallback;
}

/// Returns a YAML threshold value as a [num], or `null` when the field is
/// absent. A non-numeric value — including a quoted number like
/// `error: "15"`, which YAML deliberately reads as a string — is a config
/// type error: it surfaces as a [ConfigException] rather than being
/// silently dropped to "no gate" or coerced to a number we merely guessed
/// the author meant.
num? _asNum(Object? v) {
  if (v == null) return null;
  if (v is num) return v;
  throw ConfigException(
    'metric threshold must be a number (got ${v.runtimeType}: $v)',
  );
}

/// Builds the implicit-defaults configuration used when the file is
/// missing or has no `dartrics:` block. Centralised so every fallback
/// path emits the same merged-defaults `metricThresholds` map.
Config _defaultConfig() => Config(metricThresholds: _parseMetrics(null));

/// Thrown when the configuration file cannot be parsed or is structurally
/// invalid. CLI handlers should map this to [ExitCode.config].
class ConfigException implements Exception {
  ConfigException(this.message);
  final String message;
  @override
  String toString() => 'ConfigException: $message';
}
