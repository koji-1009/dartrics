import 'dart:io';

import 'package:path/path.dart' as p;

/// Indirection point for shelling out to `git`. Tests substitute a
/// stub runner; the production path uses [Process.run].
typedef GitProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

Future<ProcessResult> _defaultRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) => Process.run(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  stdoutEncoding: const SystemEncoding(),
  stderrEncoding: const SystemEncoding(),
);

/// Lists Dart files that changed between [ref] and `HEAD` (according to git).
///
/// Shells out to `git diff --name-only --diff-filter=AMR <ref>...HEAD --`
/// and returns the absolute paths of the changed `.dart` files. Renames
/// surface as the new path. Untracked files are not part of `git diff`
/// and are intentionally ignored.
///
/// Throws [GitDiffException] when the working directory isn't a git
/// repository, when `git` is not installed, or when [ref] cannot be
/// resolved. CLI handlers should map this to `ExitCode.data` (`65`).
Future<List<String>> changedDartFilesSince(
  String ref, {
  String? workingDirectory,
  GitProcessRunner runner = _defaultRunner,
}) async {
  final cwd = workingDirectory ?? Directory.current.path;
  final ProcessResult result;
  try {
    result = await runner('git', [
      'diff',
      '--name-only',
      '--diff-filter=AMR',
      '$ref...HEAD',
      '--',
      '*.dart',
    ], workingDirectory: cwd);
  } on ProcessException catch (e) {
    throw GitDiffException('failed to invoke git: ${e.message}');
  }
  if (result.exitCode != 0) {
    final stderr = (result.stderr as String).trim();
    throw GitDiffException(
      'git diff exited with ${result.exitCode}'
      '${stderr.isEmpty ? '' : ': $stderr'}',
    );
  }
  final stdout = result.stdout as String;
  return stdout
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map((rel) => p.normalize(p.absolute(p.join(cwd, rel))))
      .toList(growable: false);
}

/// A closed line range `[start, end]` (1-based, inclusive) in the
/// post-change version of a file.
typedef LineRange = ({int start, int end});

/// Maps each changed Dart file (absolute path) to the line ranges its
/// hunks touch in the `HEAD` version, according to
/// `git diff --unified=0 --diff-filter=AMR <ref>...HEAD -- *.dart`.
///
/// This is the function-granular sibling of [changedDartFilesSince]:
/// the ranges let callers drop scopes the diff never touched instead
/// of re-surfacing every scope in a changed file. The file set
/// (`map.keys`) differs from the `--name-only` variant in one corner:
/// a 100%-similarity rename emits no `+++` header (and no hunks), so
/// purely-renamed files drop out entirely — nothing in them changed.
///
/// Throws [GitDiffException] under the same conditions as
/// [changedDartFilesSince].
Future<Map<String, List<LineRange>>> changedDartLineRangesSince(
  String ref, {
  String? workingDirectory,
  GitProcessRunner runner = _defaultRunner,
}) async {
  final cwd = workingDirectory ?? Directory.current.path;
  final ProcessResult result;
  try {
    result = await runner('git', [
      'diff',
      '--unified=0',
      '--diff-filter=AMR',
      '$ref...HEAD',
      '--',
      '*.dart',
    ], workingDirectory: cwd);
  } on ProcessException catch (e) {
    throw GitDiffException('failed to invoke git: ${e.message}');
  }
  if (result.exitCode != 0) {
    final stderr = (result.stderr as String).trim();
    throw GitDiffException(
      'git diff exited with ${result.exitCode}'
      '${stderr.isEmpty ? '' : ': $stderr'}',
    );
  }
  return parseUnifiedZeroRanges(result.stdout as String, cwd: cwd);
}

/// Pure parser for `git diff --unified=0` output — split out so tests
/// can exercise hunk shapes without a live repository.
///
/// Reads `+++ b/<path>` headers to track the current file and
/// `@@ -a[,b] +c[,d] @@` hunk headers for the new-file side: `+c,d`
/// covers lines `c..c+d-1`. A deletion-only hunk (`d == 0`) surfaces
/// as the single line `c` (clamped to 1) — the line the removal now
/// abuts — so a deletion inside a scope still marks that scope as
/// changed.
Map<String, List<LineRange>> parseUnifiedZeroRanges(
  String diff, {
  required String cwd,
}) {
  final ranges = <String, List<LineRange>>{};
  String? current;
  for (final line in diff.split('\n')) {
    if (line.startsWith('+++ ')) {
      current = _newSidePath(line, cwd: cwd);
      if (current != null) ranges.putIfAbsent(current, () => []);
      continue;
    }
    if (current == null) continue;
    final m = _hunkHeader.firstMatch(line);
    if (m != null) ranges[current]!.add(_newSideRange(m));
  }
  return ranges;
}

/// Resolves a `+++ <path>` header to an absolute path. Returns `null`
/// for the `/dev/null` new side — defensive, since `--diff-filter=AMR`
/// excludes the deletions that would produce it.
String? _newSidePath(String line, {required String cwd}) {
  var path = line.substring(4).trim();
  if (path == '/dev/null') return null;
  if (path.startsWith('b/')) path = path.substring(2);
  return p.normalize(p.absolute(p.join(cwd, path)));
}

/// Computes the new-file range for a matched `@@` header: `+c,d`
/// covers `c..c+d-1`. A deletion-only hunk (`d == 0`) surfaces as the
/// single line the removal abuts, clamped to 1.
LineRange _newSideRange(RegExpMatch m) {
  final start = int.parse(m.group(1)!);
  final count = m.group(2) == null ? 1 : int.parse(m.group(2)!);
  if (count == 0) {
    final marker = start < 1 ? 1 : start;
    return (start: marker, end: marker);
  }
  return (start: start, end: start + count - 1);
}

final _hunkHeader = RegExp(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@');

/// Thrown by [changedDartFilesSince] when git is missing, the cwd is not
/// a git repository, or the supplied ref doesn't resolve.
class GitDiffException implements Exception {
  GitDiffException(this.message);
  final String message;
  @override
  String toString() => 'GitDiffException: $message';
}
