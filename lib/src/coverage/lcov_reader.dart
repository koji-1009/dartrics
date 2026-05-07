import 'dart:io';

/// Per-file coverage extracted from an `lcov.info` record.
class FileCoverage {
  const FileCoverage({
    required this.path,
    required this.lineHits,
    required this.branchHits,
  });

  final String path;

  /// `line number` → `hit count`. Lines absent from the map weren't
  /// reported in the lcov record (typically blank or comment-only).
  final Map<int, int> lineHits;

  /// `(line, branchId)` → `hit count`. Empty when the lcov source
  /// didn't include `BRDA:` records.
  final Map<(int, int), int> branchHits;

  /// Fraction of executable lines covered in `[start, end]`. Returns
  /// 1.0 when no executable lines fall inside the range (e.g. abstract
  /// declaration spans).
  double lineCoverageInRange(int start, int end) {
    var total = 0;
    var hit = 0;
    for (final entry in lineHits.entries) {
      if (entry.key < start || entry.key > end) continue;
      total++;
      if (entry.value > 0) hit++;
    }
    if (total == 0) return 1.0;
    return hit / total;
  }

  /// Branch coverage for `[start, end]`. Returns `null` when no branch
  /// records are available for any line in the range — the caller can
  /// then fall back to line coverage.
  double? branchCoverageInRange(int start, int end) {
    var total = 0;
    var hit = 0;
    for (final entry in branchHits.entries) {
      final line = entry.key.$1;
      if (line < start || line > end) continue;
      total++;
      if (entry.value > 0) hit++;
    }
    if (total == 0) return null;
    return hit / total;
  }
}

/// Index of every file mentioned in an lcov.info file. Lookups are by
/// canonical absolute path.
class CoverageIndex {
  const CoverageIndex({required this.files});

  final Map<String, FileCoverage> files;

  /// Reads and parses [path]. Throws [FormatException] when the file is
  /// not parseable; missing files are surfaced as `FileSystemException`
  /// from the underlying read.
  static Future<CoverageIndex> readFile(String path) async {
    final content = await File(path).readAsString();
    return parse(content);
  }

  /// Parses an lcov.info string. Recognises `SF:`, `DA:line,count`,
  /// `BRDA:line,block,branch,count`, and `end_of_record`. Other lines
  /// are ignored.
  static CoverageIndex parse(String content) {
    final files = <String, FileCoverage>{};
    String? currentPath;
    var lineHits = <int, int>{};
    var branchHits = <(int, int), int>{};

    for (final raw in content.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('SF:')) {
        currentPath = line.substring(3);
        lineHits = <int, int>{};
        branchHits = <(int, int), int>{};
        continue;
      }
      if (line.startsWith('DA:')) {
        _parseDA(line, lineHits);
        continue;
      }
      if (line.startsWith('BRDA:')) {
        _parseBRDA(line, branchHits);
        continue;
      }
      if (line == 'end_of_record' && currentPath != null) {
        files[currentPath] = FileCoverage(
          path: currentPath,
          lineHits: Map.unmodifiable(lineHits),
          branchHits: Map.unmodifiable(branchHits),
        );
        currentPath = null;
      }
    }
    return CoverageIndex(files: Map.unmodifiable(files));
  }

  static void _parseDA(String line, Map<int, int> lineHits) {
    final parts = line.substring(3).split(',');
    if (parts.length < 2) {
      throw FormatException('malformed DA line: $line');
    }
    lineHits[int.parse(parts[0])] = int.parse(parts[1]);
  }

  static void _parseBRDA(String line, Map<(int, int), int> branchHits) {
    final parts = line.substring(5).split(',');
    if (parts.length < 4) {
      throw FormatException('malformed BRDA line: $line');
    }
    final ln = int.parse(parts[0]);
    final branchId = int.parse(parts[2]);
    // `-` means the branch was never evaluated; treat as 0 hits.
    final count = parts[3] == '-' ? 0 : int.parse(parts[3]);
    branchHits[(ln, branchId)] = count;
  }

  /// Returns the [FileCoverage] for [absolutePath], or `null` when the
  /// path wasn't covered. Comparison is exact-string; callers should
  /// normalize paths before lookup.
  FileCoverage? forFile(String absolutePath) => files[absolutePath];
}
