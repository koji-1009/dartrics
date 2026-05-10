import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../models/analysis_report.dart';

/// Default per-mode snapshot file paths.
const String _cacheDefaultPath = '.dart_tool/dartrics/snapshot.json';
const String _baselineDefaultPath = 'dartrics-snapshot.json';

/// Resolves the CLI `--snapshot` value against the YAML-derived
/// [config]. The CLI override always wins; an unrecognised string is
/// treated as an explicit custom path, so users can pass a one-shot
/// `--snapshot path/to/file.json`.
SnapshotConfig resolveSnapshotConfig(SnapshotConfig config, String? cliValue) =>
    switch (cliValue) {
      null => config,
      'cache' => SnapshotConfig(mode: SnapshotMode.cache, path: config.path),
      'baseline' => SnapshotConfig(
        mode: SnapshotMode.baseline,
        path: config.path,
      ),
      'none' || 'off' => const SnapshotConfig(mode: SnapshotMode.none),
      _ => SnapshotConfig(mode: config.mode, path: cliValue),
    };

/// Resolves the on-disk path implied by [config], rooted at [root].
/// Returns `null` when snapshot mode is `none` (caller should skip both
/// reads and writes).
String? snapshotPathFor(SnapshotConfig config, String root) {
  final relative = switch (config.mode) {
    .none => null,
    .cache => config.path ?? _cacheDefaultPath,
    .baseline => config.path ?? _baselineDefaultPath,
  };
  if (relative == null) return null;
  return p.normalize(p.join(root, relative));
}

/// In-memory representation of a snapshot file, keyed by canonical
/// file path.
class Snapshot {
  Snapshot({required this.entries});

  /// Reads the snapshot file at [path]. Returns an empty snapshot when
  /// the file is missing — first-run AI loops should still emit the
  /// full result.
  factory Snapshot.read(String path) {
    final file = File(path);
    if (!file.existsSync()) return Snapshot(entries: const {});
    final raw = file.readAsStringSync();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) return Snapshot(entries: const {});
    final files = decoded['analyzedFiles'];
    if (files is! List) return Snapshot(entries: const {});
    final entries = <String, String>{};
    for (final entry in files) {
      if (entry is! Map) continue;
      final p = entry['path'];
      final h = entry['sha256'];
      if (p is String && h is String) entries[p] = h;
    }
    return Snapshot(entries: entries);
  }

  final Map<String, String> entries;

  /// Returns the subset of [files] whose hash differs from this
  /// snapshot. Files that are present here but not on the new run side
  /// (deleted) are not surfaced; the caller decides whether to emit
  /// results for files that no longer exist.
  Set<String> changedPaths(List<AnalyzedFile> files) {
    final out = <String>{};
    for (final f in files) {
      if (entries[f.path] != f.sha256) out.add(f.path);
    }
    return out;
  }
}

/// Computes the per-file hash list for the analysis run.
List<AnalyzedFile> hashFiles(Iterable<({String path, String content})> units) {
  final out = <AnalyzedFile>[];
  for (final u in units) {
    final digest = sha256.convert(utf8.encode(u.content));
    out.add(AnalyzedFile(path: u.path, sha256: digest.toString()));
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

/// Persists the snapshot — file hashes only, intentionally — to [path].
void writeSnapshot(String path, List<AnalyzedFile> files) {
  final file = File(path)..parent.createSync(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  file.writeAsStringSync(
    encoder.convert({
      'version': '1',
      'analyzedFiles': files.map((f) => f.toJson()).toList(),
    }),
  );
}
