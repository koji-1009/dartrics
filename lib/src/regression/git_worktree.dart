import 'dart:io';

import 'package:path/path.dart' as p;

/// Directory-name prefix shared by every temp worktree [GitWorktree.add]
/// creates. [GitWorktree.pruneStale] only ever touches registrations
/// whose directory basename carries this prefix.
const String worktreeDirPrefix = 'dartrics_worktree_';

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
    final tmp = await Directory.systemTemp.createTemp(worktreeDirPrefix);
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

  /// Removes leftover [worktreeDirPrefix] registrations that an earlier
  /// run left behind because it died before [dispose] ran (SIGPIPE from
  /// a closed output pipe, SIGKILL, power loss). Registrations would
  /// otherwise accumulate in `.git/worktrees` forever — each run mounts
  /// a fresh random-suffix directory, so nothing ever reclaims them.
  ///
  /// Only worktrees whose directory basename starts with
  /// [worktreeDirPrefix] are touched. A matching registration whose
  /// directory still exists is dropped with `git worktree remove
  /// --force`; one whose directory is already gone (temp cleaner, OS
  /// reboot) is unreachable for `remove`, so `git worktree prune` runs
  /// once at the end — only when such an entry was seen, since prune is
  /// repository-global. Best-effort throughout: a failing `git` call
  /// (e.g. [from] is not a repository) is ignored — the subsequent
  /// [add] surfaces the real error to the user.
  static Future<void> pruneStale({String from = '.'}) async {
    final ProcessResult list;
    try {
      list = await Process.run('git', [
        'worktree',
        'list',
        '--porcelain',
      ], workingDirectory: from);
    } on ProcessException {
      // Nonexistent working directory (or no git binary). Same
      // best-effort deal as a non-zero exit below.
      return;
    }
    if (list.exitCode != 0) return;
    var needsPrune = false;
    for (final line in (list.stdout as String).split('\n')) {
      if (!line.startsWith('worktree ')) continue;
      final path = line.substring('worktree '.length).trim();
      if (!p.basename(path).startsWith(worktreeDirPrefix)) continue;
      if (!Directory(path).existsSync()) {
        needsPrune = true;
        continue;
      }
      await Process.run('git', [
        'worktree',
        'remove',
        '--force',
        path,
      ], workingDirectory: from);
    }
    if (needsPrune) {
      await Process.run('git', ['worktree', 'prune'], workingDirectory: from);
    }
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
