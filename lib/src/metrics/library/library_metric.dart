import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../metric.dart';

/// Per-file precomputed information for the library-level metrics.
class LibraryStats {
  LibraryStats({
    required this.internalImports,
    required this.totalClasses,
    required this.abstractClasses,
  });

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
      final internal = entry.value.internalImports.where(stats.containsKey);
      for (final imported in internal) {
        reverse.putIfAbsent(imported, () => <String>{}).add(entry.key);
      }
    }
    return reverse;
  }

  final Map<String, LibraryStats> stats;
  final Map<String, Set<String>> importers;

  static LibraryIndex build(
    List<({String path, ResolvedUnitResult unit})> files,
  ) {
    final ctx = _ImportResolutionContext(
      pathSet: files.map((f) => f.path).toSet(),
    );
    final stats = <String, LibraryStats>{};
    for (final entry in files) {
      stats[entry.path] = _statsFor(entry.path, entry.unit.unit, ctx);
    }
    return LibraryIndex._(stats: stats, importers: ctx.importers);
  }

  static LibraryStats _statsFor(
    String path,
    CompilationUnit unit,
    _ImportResolutionContext ctx,
  ) {
    final imports = _resolveImports(path, unit, ctx);
    final classCounts = _countClasses(unit);
    return LibraryStats(
      internalImports: imports,
      totalClasses: classCounts.total,
      abstractClasses: classCounts.abstractCount,
    );
  }

  static Set<String> _resolveImports(
    String path,
    CompilationUnit unit,
    _ImportResolutionContext ctx,
  ) {
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
      if (ctx.pathSet.contains(candidate)) {
        imports.add(candidate);
        ctx.importers.putIfAbsent(candidate, () => <String>{}).add(path);
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
  const LibraryMetric();

  String get id;
  bool get defaultEnabled => true;

  /// One-paragraph explanation of what the metric measures, surfaced by
  /// `dartrics rules` and the auto-explain block.
  String get rationale;

  /// Concrete refactor moves to take when the metric trips.
  List<String> get refactorHints;

  /// Original sources for the metric. See [FunctionMetric.references].
  /// Every concrete library metric ships with a citation, so this getter
  /// is abstract — there is no `const []` default to fall back on.
  List<String> get references;

  /// Direction in which the value moves when the code gets healthier.
  /// See `FunctionMetric.polarity`.
  MetricPolarity get polarity => MetricPolarity.neutral;

  num compute(LibraryMetricInput input);
}

/// Mutable bookkeeping shared across `_resolveImports` calls during a
/// single `LibraryIndex.build` pass.
class _ImportResolutionContext {
  _ImportResolutionContext({required this.pathSet});

  final Set<String> pathSet;
  final Map<String, Set<String>> importers = {};
}
