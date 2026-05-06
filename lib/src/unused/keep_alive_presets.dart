/// Pre-shipped sets of annotation names that keep their annotated
/// declarations alive for the unused-public-API detector.
///
/// Each preset corresponds to a popular Dart code-generation package.
/// When the generated counterpart (`.g.dart`, `.freezed.dart`, …) is
/// missing — typical on a fresh checkout, before
/// `dart run build_runner build` has run — the annotated source class
/// would otherwise look unreachable. Opting in to the relevant preset
/// suppresses the false positive without forcing the user to enumerate
/// each annotation by hand.
///
/// Users opt in via `analysis_options.yaml`:
///
/// ```yaml
/// dartrics:
///   unused:
///     presets:
///       - freezed
///       - json_serializable
/// ```
///
/// Unknown preset names are silently ignored so adding a preset to the
/// list never breaks an older dartrics version.
const Map<String, List<String>> keepAlivePresets = {
  'freezed': ['freezed', 'Freezed', 'unfreezed'],
  'json_serializable': ['JsonSerializable', 'JsonEnum'],
  'dart_mappable': ['MappableClass', 'MappableEnum', 'MappableLib'],
  'go_router_builder': [
    'TypedGoRoute',
    'TypedShellRoute',
    'TypedStatefulShellRoute',
  ],
  'auto_route': ['RoutePage', 'AutoRouterConfig'],
};

/// Expands a list of preset names to the union of their annotation sets.
/// Unknown names are silently ignored.
Set<String> expandPresets(Iterable<String> presetNames) {
  final out = <String>{};
  for (final name in presetNames) {
    final preset = keepAlivePresets[name];
    if (preset != null) out.addAll(preset);
  }
  return out;
}
