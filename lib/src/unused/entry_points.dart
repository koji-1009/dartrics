import '../config/config.dart';
import 'declaration_record.dart';
import 'keep_alive_presets.dart';

/// Finds the [DeclarationRecord]s that should be treated as reachability
/// roots according to [config].
List<DeclarationRecord> resolveEntryPoints(
  List<DeclarationRecord> declarations,
  UnusedConfig config,
) {
  final roots = <DeclarationRecord>{};
  final entrySimpleNames = <String>{};
  for (final ep in config.entryPoints) {
    if (!ep.startsWith('@pragma:')) entrySimpleNames.add(ep);
  }
  final keepAliveAnnotations = <String>{
    ...config.ignoreAnnotations,
    // Every codegen preset is always honored as a keep-alive root.
    ...allKeepAliveAnnotations,
  };
  for (final d in declarations) {
    if (entrySimpleNames.contains(d.name)) roots.add(d);
    if (d.hasVmEntryPointPragma) roots.add(d);
    if (keepAliveAnnotations.any(d.annotations.contains)) {
      // Annotations from `ignore-annotations` plus every codegen preset
      // (freezed / json_serializable / dart_mappable / go_router_builder /
      // auto_route / riverpod / injectable / hive / drift) keep their
      // declarations alive even when nothing references them — useful
      // when the matching `.g.dart` / `.freezed.dart` partner hasn't
      // been generated yet.
      roots.add(d);
    }
    if (config.excludeExported && _isLibraryPublic(d.location.path)) {
      // Convention: anything under `lib/` but outside `lib/src/` is part of
      // the package's public API and therefore an implicit reachability
      // root. Disabling `excludeExported` reverts to strict mode where even
      // exported declarations need an explicit caller.
      roots.add(d);
    }
  }
  return roots.toList();
}

bool _isLibraryPublic(String path) {
  final unix = path.replaceAll(r'\', '/');
  if (!unix.contains('/lib/')) return false;
  if (unix.contains('/lib/src/')) return false;
  return true;
}
