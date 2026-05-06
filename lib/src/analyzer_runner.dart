import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';

/// Suffixes that mark a Dart file as machine-generated. Metrics computed
/// on these would be both noise (the human didn't write the code) and
/// unstable (regenerating the file changes the numbers). Dropped from
/// `collectDartFiles` by default.
const _generatedSuffixes = {
  '.g.dart',
  '.freezed.dart',
  '.gr.dart',
  '.config.dart',
  '.mocks.dart',
  '.pb.dart',
  '.pbenum.dart',
  '.pbgrpc.dart',
  '.pbjson.dart',
  '.pbserver.dart',
  '.gen.dart',
};

/// Thin abstraction layer over `package:analyzer`.
///
/// Concentrates every direct call into the analyzer API in this file so the
/// rest of dartrics is insulated from analyzer's frequent breaking changes.
class AnalyzerRunner {
  AnalyzerRunner({
    required this.roots,
    this.exclude = const [],
    this.includeGenerated = false,
    int? concurrency,
  }) : concurrency = concurrency ?? defaultConcurrency();

  /// Default parallelism for [resolveAll]. Mirrors the host's CPU count
  /// so analyzer driver work overlaps file I/O, but never goes below 1
  /// (host might report 0 in odd VMs) or above 16 (diminishing returns
  /// + memory pressure on the analyzer).
  static int defaultConcurrency() {
    final cpus = Platform.numberOfProcessors;
    if (cpus <= 0) return 1;
    if (cpus > 16) return 16;
    return cpus;
  }

  final List<String> roots;
  final List<String> exclude;

  /// Maximum concurrent [resolve] calls issued by [resolveAll]. The
  /// analyzer driver internally serializes work, so the win is mostly
  /// I/O / parsing overlap; a value larger than `numberOfProcessors`
  /// rarely pays off.
  final int concurrency;

  /// When `false` (default), files matching one of [_generatedSuffixes]
  /// are skipped during file collection. Set to `true` if a project really
  /// wants metrics on its generated output.
  final bool includeGenerated;

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
    if (!includeGenerated && _isGenerated(path)) return false;
    final relative = p.relative(path, from: root);
    return !excluders.any((g) => g.matches(relative));
  }

  bool _isGenerated(String path) {
    return _generatedSuffixes.any(path.endsWith);
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
  /// analyzer can't fully resolve. Runs up to [concurrency] resolves in
  /// flight at once via `package:pool`; ordering of the output list
  /// follows the alphabetical file list so reports stay deterministic.
  Future<List<({String path, ResolvedUnitResult unit})>> resolveAll() async {
    final files = await collectDartFiles();
    if (files.isEmpty) return const [];
    if (concurrency <= 1 || files.length == 1) {
      final out = <({String path, ResolvedUnitResult unit})>[];
      for (final path in files) {
        final unit = await resolve(path);
        if (unit != null) out.add((path: path, unit: unit));
      }
      return out;
    }
    final pool = Pool(concurrency);
    try {
      final results = await Future.wait([
        for (final path in files)
          pool.withResource(
            () async => (path: path, unit: await resolve(path)),
          ),
      ]);
      return [
        for (final r in results)
          if (r.unit != null) (path: r.path, unit: r.unit!),
      ];
    } finally {
      await pool.close();
    }
  }
}
