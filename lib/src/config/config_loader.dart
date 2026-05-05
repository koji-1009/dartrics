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
  );
}

Map<String, MetricThresholds> _parseMetrics(Object? node) {
  if (node is! YamlMap) return const {};
  final map = <String, MetricThresholds>{};
  for (final entry in node.entries) {
    final key = entry.key.toString();
    final value = entry.value;
    if (value is YamlMap) {
      map[key] = MetricThresholds(
        warning: _asNum(value['warning']),
        error: _asNum(value['error']),
      );
    } else if (value is num) {
      map[key] = MetricThresholds(warning: value);
    }
  }
  return map;
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
