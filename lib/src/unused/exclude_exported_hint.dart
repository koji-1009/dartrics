import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../config/config.dart';

/// Warning line for a run that found nothing only because
/// `exclude-exported` rooted an app's whole `lib/`, or `null` when the
/// run does not look like that.
///
/// `exclude-exported: true` treats everything under `lib/` outside
/// `lib/src/` as public API. An app keeps its code there without a
/// `lib/src/` split, so every declaration becomes a root and the report
/// is empty. The app signal is `publish_to: none` in the root
/// `pubspec.yaml` — what `flutter create` writes. `lib/main.dart` is
/// deliberately not a signal: analyzer plugins (dartrics included) ship
/// one as a package.
String? excludeExportedAppHint({
  required String root,
  required UnusedConfig config,
  required int findingCount,
}) {
  if (!config.excludeExported || findingCount > 0) return null;
  if (!_isUnpublished(root)) return null;
  return 'dartrics: no unused declarations, but `unused.exclude-exported` '
      'is true and pubspec.yaml sets `publish_to: none`. Every declaration '
      'under lib/ outside lib/src/ is a reachability root, which in an app '
      'is usually all of them. Set '
      '`dartrics: { unused: { exclude-exported: false } }` to check an app.';
}

/// Writes the [excludeExportedAppHint] line to [sink] when there is one.
void writeExcludeExportedAppHint(
  StringSink sink, {
  required String root,
  required UnusedConfig config,
  required int findingCount,
}) {
  final hint = excludeExportedAppHint(
    root: root,
    config: config,
    findingCount: findingCount,
  );
  if (hint != null) sink.writeln(hint);
}

bool _isUnpublished(String root) {
  final pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return false;
  final Object? parsed;
  try {
    parsed = loadYaml(pubspec.readAsStringSync());
  } on YamlException {
    return false;
  }
  return parsed is YamlMap && parsed['publish_to'] == 'none';
}
