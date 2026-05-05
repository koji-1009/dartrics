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
  AnalyzerRunner({required this.roots, this.exclude = const []});

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
      await _collectFromRoot(root, excluders, results);
    }
    results.sort();
    return results;
  }

  Future<void> _collectFromRoot(
    String root,
    List<Glob> excluders,
    List<String> out,
  ) async {
    final dir = Directory(root);
    if (!dir.existsSync()) {
      if (FileSystemEntity.isFileSync(root) && root.endsWith('.dart')) {
        out.add(p.normalize(p.absolute(root)));
      }
      return;
    }
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (_isCollectableDart(entity, root, excluders)) {
        out.add(p.normalize(p.absolute(entity.path)));
      }
    }
  }

  bool _isCollectableDart(
    FileSystemEntity entity,
    String root,
    List<Glob> excluders,
  ) {
    if (entity is! File) return false;
    final path = entity.path;
    if (!path.endsWith('.dart')) return false;
    if (path.contains('${p.separator}.dart_tool${p.separator}')) return false;
    final relative = p.relative(path, from: root);
    return !excluders.any((g) => g.matches(relative));
  }

  /// Resolves a single Dart file to a [ResolvedUnitResult]. Returns `null`
  /// for paths that the analyzer cannot resolve (e.g. files outside any
  /// package context).
  Future<ResolvedUnitResult?> resolve(String absolutePath) async {
    final context = collection.contextFor(absolutePath);
    final result = await context.currentSession.getResolvedUnit(absolutePath);
    return result is ResolvedUnitResult ? result : null;
  }

  /// Resolves every Dart file under [roots], skipping paths that the
  /// analyzer can't fully resolve.
  Future<List<({String path, ResolvedUnitResult unit})>> resolveAll() async {
    final files = await collectDartFiles();
    final out = <({String path, ResolvedUnitResult unit})>[];
    for (final path in files) {
      final unit = await resolve(path);
      if (unit != null) out.add((path: path, unit: unit));
    }
    return out;
  }
}
