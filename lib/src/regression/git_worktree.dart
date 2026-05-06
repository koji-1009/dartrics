import 'dart:io';

/// A short-lived `git worktree add --detach <path> <ref>` that gets
/// cleaned up via [dispose]. Used by `dartrics regression` to mount
/// historical commits without disturbing the main checkout.
class GitWorktree {
  GitWorktree._({required this.path, required this.from});

  /// Creates a temporary worktree at [ref] under a fresh
  /// `Directory.systemTemp` path. The repository to base the worktree
  /// on is taken from [from] (defaults to the current working
  /// directory). Caller MUST call [dispose] when finished.
  static Future<GitWorktree> add({
    required String ref,
    String from = '.',
  }) async {
    final tmp = await Directory.systemTemp.createTemp('dartrics_worktree_');
    final result = await Process.run('git', [
      'worktree',
      'add',
      '--detach',
      tmp.path,
      ref,
    ], workingDirectory: from);
    if (result.exitCode != 0) {
      // Best-effort cleanup of the empty temp dir before propagating.
      await tmp.delete(recursive: true);
      throw GitWorktreeException(
        'git worktree add ${result.exitCode}: '
        '${(result.stderr as Object).toString().trim()}',
      );
    }
    return GitWorktree._(path: tmp.path, from: from);
  }

  /// Absolute path to the worktree root.
  final String path;

  /// The repo the worktree was anchored on.
  final String from;

  bool _disposed = false;

  /// Removes the worktree. Idempotent. `git worktree remove --force`
  /// also deletes the on-disk directory, so no extra cleanup is needed
  /// in the happy path; if git fails the temp dir is left behind, which
  /// is acceptable for a cleanup helper.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Process.run('git', [
      'worktree',
      'remove',
      '--force',
      path,
    ], workingDirectory: from);
  }
}

/// Thrown when the git CLI refuses to create a worktree (bad ref,
/// outside a repo, etc.).
class GitWorktreeException implements Exception {
  GitWorktreeException(this.message);
  final String message;
  @override
  String toString() => 'GitWorktreeException: $message';
}
