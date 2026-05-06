import 'dart:io';

import 'package:path/path.dart' as p;

import 'lcov_reader.dart';

/// Default path the CLI auto-loads when `--coverage` isn't set.
const String defaultCoveragePath = 'coverage/lcov.info';

/// Resolves the user's `--coverage <path>` selection against [root]:
///
/// - `null` → auto-load `<root>/coverage/lcov.info` if it exists.
/// - `'none'` (case-insensitive) → disabled, returns `null`.
/// - any other value → load from that path; missing file is fatal
///   so the user notices typos, parse errors are surfaced as
///   `FormatException` for the caller to map to EX_DATAERR.
Future<CoverageIndex?> loadCoverage({
  required String? cliValue,
  required String root,
}) async {
  if (cliValue != null && cliValue.toLowerCase() == 'none') return null;
  final path = cliValue ?? p.join(root, defaultCoveragePath);
  final file = File(path);
  if (!file.existsSync()) {
    if (cliValue == null) {
      // Auto-discovery miss is non-fatal; just disabled.
      return null;
    }
    throw CoverageLoadException('coverage file not found: $path');
  }
  return CoverageIndex.readFile(path);
}

/// Thrown when a user-supplied `--coverage <path>` doesn't exist or is
/// otherwise unloadable. Auto-discovery misses don't throw.
class CoverageLoadException implements Exception {
  CoverageLoadException(this.message);
  final String message;
  @override
  String toString() => 'CoverageLoadException: $message';
}
