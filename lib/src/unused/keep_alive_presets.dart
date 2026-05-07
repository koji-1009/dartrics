/// Annotation names that keep their annotated declarations alive for
/// the unused-public-API detector.
///
/// Each entry corresponds to a popular Dart code-generation package.
/// When the generated counterpart (`.g.dart`, `.freezed.dart`,
/// `.config.dart`, …) is missing — typical on a fresh checkout, before
/// `dart run build_runner build` has run — an annotated source class
/// would otherwise look unreachable. dartrics treats every annotation
/// listed here as an implicit reachability root so the detector
/// doesn't false-positive on idiomatic codegen-driven code.
///
/// **All presets are active out of the box** as of 0.1.0. The
/// per-package opt-in (`dartrics: { unused: { presets: [...] } }`) was
/// dropped because the cost of always-on is essentially zero — these
/// names are PascalCase identifiers from specific external packages,
/// so listing one your project doesn't use just adds an unused entry
/// to a Set. Listing `presets:` in `analysis_options.yaml` is still
/// accepted for backward compatibility, but the value is ignored.
const Map<String, List<String>> keepAlivePresets = {
  // freezed (2.x and 3.x)
  'freezed': ['freezed', 'Freezed', 'unfreezed'],
  // json_serializable
  'json_serializable': ['JsonSerializable', 'JsonEnum'],
  // dart_mappable
  'dart_mappable': ['MappableClass', 'MappableEnum', 'MappableLib'],
  // go_router_builder
  'go_router_builder': [
    'TypedGoRoute',
    'TypedShellRoute',
    'TypedStatefulShellRoute',
  ],
  // auto_route
  'auto_route': ['RoutePage', 'AutoRouterConfig'],
  // riverpod_generator (Riverpod 2.x annotation API)
  'riverpod': ['riverpod', 'Riverpod'],
  // injectable
  'injectable': [
    'injectable',
    'Injectable',
    'singleton',
    'Singleton',
    'lazySingleton',
    'LazySingleton',
    'factoryMethod',
    'FactoryMethod',
    'module',
    'Module',
    'InjectableInit',
  ],
  // hive / hive_ce
  'hive': ['HiveType', 'HiveField'],
  // drift
  'drift': [
    'DriftDatabase',
    'DriftAccessor',
    'DataClassName',
    'TableIndex',
    'UseRowClass',
  ],
};

/// The full union of every preset's annotation names. Used as the
/// always-on keep-alive set for the unused detector. Computing once at
/// init time keeps the per-declaration loop cheap.
final Set<String> allKeepAliveAnnotations = {
  for (final names in keepAlivePresets.values) ...names,
};

/// Expands a list of preset names to the union of their annotation sets.
/// Unknown names are silently ignored. Retained for backward
/// compatibility — the engine itself uses [allKeepAliveAnnotations] now.
Set<String> expandPresets(Iterable<String> presetNames) {
  final out = <String>{};
  for (final name in presetNames) {
    final preset = keepAlivePresets[name];
    if (preset != null) out.addAll(preset);
  }
  return out;
}
