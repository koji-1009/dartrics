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

/// Thrown by [changedDartFilesSince] when git is missing, the cwd is not
/// a git repository, or the supplied ref doesn't resolve.
class GitDiffException implements Exception {
  GitDiffException(this.message);
  final String message;
  @override
  String toString() => 'GitDiffException: $message';
}
