import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

/// Per-file precomputed information for the library-level metrics.
class LibraryStats {
  LibraryStats({
    required this.path,
    required this.internalImports,
    required this.totalClasses,
    required this.abstractClasses,
  });

  final String path;

  /// Absolute paths of project-internal files imported by this file.
  final Set<String> internalImports;

  /// Number of class-like declarations in this file (`class` and `mixin`).
  final int totalClasses;

  /// Subset of `totalClasses` that are abstract (`abstract class`,
  /// `mixin`, or class with no concrete members).
  final int abstractClasses;
}

class LibraryIndex {
  LibraryIndex._({
    required this.stats,
    required this.importers,
  });

  /// Constructs a [LibraryIndex] directly from precomputed stats. Used by
  /// tests that don't want to spin up a full analyzer context.
  LibraryIndex.fromStats(this.stats) : importers = _deriveImporters(stats);

  static Map<String, Set<String>> _deriveImporters(
    Map<String, LibraryStats> stats,
  ) {
    final reverse = <String, Set<String>>{};
    for (final entry in stats.entries) {
      for (final imported in entry.value.internalImports) {
        if (stats.containsKey(imported)) {
          reverse.putIfAbsent(imported, () => <String>{}).add(entry.key);
        }
      }
    }
    return reverse;
  }

  final Map<String, LibraryStats> stats;
  final Map<String, Set<String>> importers;

  static LibraryIndex build(
    List<({String path, ResolvedUnitResult unit})> files,
  ) {
    final pathSet = files.map((f) => f.path).toSet();
    final stats = <String, LibraryStats>{};
    final importers = <String, Set<String>>{};

    for (final entry in files) {
      final path = entry.path;
      final dir = p.dirname(path);
      final imports = <String>{};
      var totalClasses = 0;
      var abstractClasses = 0;

      for (final directive in entry.unit.unit.directives) {
        if (directive is! ImportDirective) continue;
        final uri = directive.uri.stringValue;
        if (uri == null) continue;
        if (uri.startsWith('dart:')) continue;
        if (uri.startsWith('package:')) {
          // Cross-package: only counted toward Ce, never resolvable to a
          // project-internal path here.
          imports.add(uri);
          continue;
        }
        // Relative import within the project.
        final candidate = p.normalize(p.join(dir, uri));
        if (pathSet.contains(candidate)) {
          imports.add(candidate);
          importers.putIfAbsent(candidate, () => <String>{}).add(path);
        } else {
          imports.add(uri);
        }
      }

      for (final decl in entry.unit.unit.declarations) {
        if (decl is ClassDeclaration) {
          totalClasses++;
          if (decl.abstractKeyword != null) abstractClasses++;
        } else if (decl is MixinDeclaration) {
          totalClasses++;
          abstractClasses++;
        }
      }

      stats[path] = LibraryStats(
        path: path,
        internalImports: imports,
        totalClasses: totalClasses,
        abstractClasses: abstractClasses,
      );
    }

    return LibraryIndex._(stats: stats, importers: importers);
  }
}

class LibraryMetricInput {
  LibraryMetricInput({required this.path, required this.index});
  final String path;
  final LibraryIndex index;

  LibraryStats get stats => index.stats[path]!;
}

abstract class LibraryMetric {
  String get id;
  num compute(LibraryMetricInput input);
}
