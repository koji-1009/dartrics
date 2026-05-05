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
  LibraryIndex._({required this.stats, required this.importers});

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
      final imports = _resolveImports(
        path: entry.path,
        unit: entry.unit.unit,
        pathSet: pathSet,
        importers: importers,
      );
      final classCounts = _countClasses(entry.unit.unit);
      stats[entry.path] = LibraryStats(
        path: entry.path,
        internalImports: imports,
        totalClasses: classCounts.total,
        abstractClasses: classCounts.abstractCount,
      );
    }

    return LibraryIndex._(stats: stats, importers: importers);
  }

  static Set<String> _resolveImports({
    required String path,
    required CompilationUnit unit,
    required Set<String> pathSet,
    required Map<String, Set<String>> importers,
  }) {
    final dir = p.dirname(path);
    final imports = <String>{};
    for (final directive in unit.directives) {
      if (directive is! ImportDirective) continue;
      final uri = directive.uri.stringValue;
      if (uri == null || uri.startsWith('dart:')) continue;
      if (uri.startsWith('package:')) {
        imports.add(uri);
        continue;
      }
      final candidate = p.normalize(p.join(dir, uri));
      if (pathSet.contains(candidate)) {
        imports.add(candidate);
        importers.putIfAbsent(candidate, () => <String>{}).add(path);
      } else {
        imports.add(uri);
      }
    }
    return imports;
  }

  static ({int total, int abstractCount}) _countClasses(CompilationUnit unit) {
    var total = 0;
    var abstractCount = 0;
    for (final decl in unit.declarations) {
      if (decl is ClassDeclaration) {
        total++;
        if (decl.abstractKeyword != null) abstractCount++;
      } else if (decl is MixinDeclaration) {
        total++;
        abstractCount++;
      }
    }
    return (total: total, abstractCount: abstractCount);
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
