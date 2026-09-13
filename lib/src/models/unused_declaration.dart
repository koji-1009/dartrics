import 'source_location.dart';

enum UnusedKind {
  function,
  method,
  klass,
  field,
  typedef,
  enumValue,
  extension,
}

/// Stable, user-facing string for [UnusedKind]. The two Dart-language
/// quirks (`class` is reserved → `klass`; CLI conventions don't use
/// camelCase → `enumValue`) are remapped so the JSON schema, the
/// `--filter` flag, and `--help` text all agree on the same set of
/// names. Internal Dart code keeps using the [UnusedKind] enum
/// values; only serialised forms go through [unusedKindJsonName].
String unusedKindJsonName(UnusedKind kind) => switch (kind) {
  UnusedKind.klass => 'class',
  UnusedKind.enumValue => 'enum',
  _ => kind.name,
};

/// Inverse of [unusedKindJsonName]. Returns `null` for inputs that
/// don't match any known kind so callers can surface a usage / parse
/// error instead of silently dropping the entry.
UnusedKind? unusedKindFromJsonName(String name) {
  return switch (name) {
    'function' => UnusedKind.function,
    'method' => UnusedKind.method,
    'class' => UnusedKind.klass,
    'field' => UnusedKind.field,
    'typedef' => UnusedKind.typedef,
    'enum' => UnusedKind.enumValue,
    'extension' => UnusedKind.extension,
    _ => null,
  };
}

class UnusedDeclaration {
  const UnusedDeclaration({
    required this.kind,
    required this.name,
    required this.location,
    this.writeOnly = false,
  });

  final UnusedKind kind;
  final String name;
  final SourceLocation location;

  /// True for a field a constructor assigns through `this.<name>` but
  /// nothing ever reads. Removing it also means removing that parameter
  /// and the argument at every call site, unlike a declaration nothing
  /// references at all. Added in report schema 1.4; always `false` for
  /// other kinds.
  final bool writeOnly;

  Map<String, Object?> toJson() => {
    'file': location.path,
    'name': name,
    'kind': unusedKindJsonName(kind),
    'line': location.line,
    if (writeOnly) 'writeOnly': true,
  };
}
