import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

/// Thin abstraction layer over `package:analyzer`.
///
/// Concentrates every direct call into the analyzer API in this file so the
/// rest of dartrics is insulated from analyzer's frequent breaking changes
/// (see §16 of project_plan.md).
class AnalyzerRunner {
  AnalyzerRunner({
    required this.roots,
    this.exclude = const [],
  });

  final List<String> roots;
  final List<String> exclude;

  AnalysisContextCollection? _collection;

  AnalysisContextCollection get collection {
    return _collection ??= AnalysisContextCollection(
      includedPaths: roots
          .map((r) => p.normalize(p.absolute(r)))
          .toList(growable: false),
    );
  }

  /// Recursively collects every `*.dart` file beneath [roots] excluding any
  /// path matched by [exclude] (relative-glob semantics) or any nested
  /// `.dart_tool/` directory.
  Future<List<String>> collectDartFiles() async {
    final excluders = exclude.map((g) => Glob(g)).toList(growable: false);
    final results = <String>[];

    for (final root in roots) {
      final dir = Directory(root);
      if (!dir.existsSync()) {
        if (FileSystemEntity.isFileSync(root) && root.endsWith('.dart')) {
          results.add(p.normalize(p.absolute(root)));
        }
        continue;
      }
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final path = entity.path;
        if (!path.endsWith('.dart')) continue;
        if (path.contains('${p.separator}.dart_tool${p.separator}')) continue;
        final relative = p.relative(path, from: root);
        if (excluders.any((g) => g.matches(relative))) continue;
        results.add(p.normalize(p.absolute(path)));
      }
    }

    results.sort();
    return results;
  }

  /// Resolves a single Dart file to a [ResolvedUnitResult]. Returns `null`
  /// for paths that the analyzer cannot resolve (e.g. files outside any
  /// package context).
  Future<ResolvedUnitResult?> resolve(String absolutePath) async {
    final context = collection.contextFor(absolutePath);
    final result = await context.currentSession.getResolvedUnit(absolutePath);
    return result is ResolvedUnitResult ? result : null;
  }
}
