import 'source_location.dart';

enum UnusedKind { function, method, klass, field, typedef, enumValue, extension }

class UnusedDeclaration {
  const UnusedDeclaration({
    required this.kind,
    required this.name,
    required this.location,
  });

  final UnusedKind kind;
  final String name;
  final SourceLocation location;

  Map<String, Object?> toJson() => {
        'file': location.path,
        'name': name,
        'kind': kind.name,
        'line': location.line,
      };
}
