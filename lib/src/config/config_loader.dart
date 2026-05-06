import 'dart:io';

import 'package:io/io.dart';
import 'package:logging/logging.dart';
import 'package:yaml/yaml.dart';

import 'config.dart';

final _log = Logger('config_loader');

/// Loads dartrics configuration from [path]. Falls back to defaults when the
/// file is missing or has no `dartrics:` section. Throws [_ConfigException]
/// (caller should surface as `EX_CONFIG`) for malformed content.
Future<Config> loadConfig(String path) async {
  final file = File(path);
  if (!file.existsSync()) {
    _log.fine('config file $path not found, using defaults');
    return const Config();
  }
  final source = await file.readAsString();
  final YamlMap root;
  try {
    final parsed = loadYaml(source);
    if (parsed is! YamlMap) {
      return const Config();
    }
    root = parsed;
  } on YamlException catch (e) {
    throw ConfigException('failed to parse $path: $e');
  }

  final dartrics = root['dartrics'];
  if (dartrics is! YamlMap) {
    return const Config();
  }

  return Config(
    metricThresholds: _parseMetrics(dartrics['metrics']),
    unused: _parseUnused(dartrics['unused']),
    exclude: _parseStringList(dartrics['exclude']),
    flutter: dartrics['flutter'] as bool? ?? true,
    test: dartrics['test'] as bool? ?? true,
    snapshot: _parseSnapshot(dartrics['snapshot']),
    dismissals: _parseDismissals(dartrics['dismissals']),
  );
}

DismissalConfig _parseDismissals(Object? node) {
  if (node == null) return const DismissalConfig();
  if (node is! YamlMap) {
    throw ConfigException(
      'dartrics.dismissals must be a map (got ${node.runtimeType})',
    );
  }
  final sourcesNode = node['sources'];
  bool comment;
  bool yamlSource;
  if (sourcesNode == null) {
    // Bare `dismissals:` block — both channels on by default so the user
    // does not have to enumerate them.
    comment = true;
    yamlSource = true;
  } else if (sourcesNode is YamlMap) {
    comment = sourcesNode['comment'] as bool? ?? true;
    yamlSource = sourcesNode['yaml'] as bool? ?? true;
  } else {
    throw ConfigException(
      'dartrics.dismissals.sources must be a map (got '
      '${sourcesNode.runtimeType})',
    );
  }
  if (!comment && !yamlSource) {
    throw ConfigException(
      'dartrics.dismissals: at least one dismissal source must be enabled',
    );
  }
  final requireReason = node['requireReason'] as bool? ?? true;
  final minReasonRaw = node['minReasonLength'];
  final minReason = minReasonRaw is int
      ? minReasonRaw
      : defaultDismissalMinReasonLength;
  if (minReason < 0) {
    throw ConfigException(
      'dartrics.dismissals.minReasonLength must be non-negative',
    );
  }
  final requireAuthor = node['requireAuthor'] as bool? ?? false;
  if (requireAuthor && !yamlSource) {
    throw ConfigException(
      'dartrics.dismissals.requireAuthor needs sources.yaml: true',
    );
  }
  final requireTimestamp = node['requireTimestamp'] as bool? ?? false;
  if (requireTimestamp && !yamlSource) {
    throw ConfigException(
      'dartrics.dismissals.requireTimestamp needs sources.yaml: true',
    );
  }
  final yamlPath = node['yamlPath'];
  return DismissalConfig(
    commentSource: comment,
    yamlSource: yamlSource,
    requireReason: requireReason,
    minReasonLength: minReason,
    requireAuthor: requireAuthor,
    requireTimestamp: requireTimestamp,
    yamlPath: yamlPath is String ? yamlPath : null,
  );
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
    return SnapshotConfig(mode: node ? SnapshotMode.cache : SnapshotMode.none);
  }
  return const SnapshotConfig();
}

SnapshotMode _modeFromString(String raw) {
  switch (raw) {
    case 'cache':
      return SnapshotMode.cache;
    case 'baseline':
      return SnapshotMode.baseline;
    case 'none':
    case 'off':
      return SnapshotMode.none;
    default:
      throw ConfigException(
        'unknown snapshot mode "$raw" (expected cache | baseline | none)',
      );
  }
}

Map<String, MetricThresholds> _parseMetrics(Object? node) {
  if (node is! YamlMap) return const {};
  final map = <String, MetricThresholds>{};
  for (final entry in node.entries) {
    final t = _thresholdsFromYaml(entry.value);
    if (t != null) map[entry.key.toString()] = t;
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
    presets: _parseStringList(node['presets']),
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

num? _asNum(Object? v) => v is num ? v : null;

/// Thrown when the configuration file cannot be parsed or is structurally
/// invalid. CLI handlers should map this to [ExitCode.config].
class ConfigException implements Exception {
  ConfigException(this.message);
  final String message;
  @override
  String toString() => 'ConfigException: $message';
}
