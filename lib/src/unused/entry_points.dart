import '../config/config.dart';
import 'declaration_record.dart';

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
  for (final d in declarations) {
    if (entrySimpleNames.contains(d.name)) roots.add(d);
    if (d.hasVmEntryPointPragma) roots.add(d);
    if (config.ignoreAnnotations.any(d.annotations.contains)) {
      // Treating "ignored annotations" as roots ensures their declarations
      // are never reported as unused even when nothing references them.
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
