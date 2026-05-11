/// Position of a metric or violation within a Dart source file.
class SourceLocation {
  const SourceLocation({
    required this.path,
    required this.line,
    required this.column,
  });

  final String path;
  final int line;
  final int column;
}
