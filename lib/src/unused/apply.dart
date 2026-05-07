import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

import '../models/unused_declaration.dart';

/// Outcome of one declaration's deletion attempt.
enum ApplyOutcome {
  /// Declaration's source range was deleted from the file.
  deleted,

  /// Declaration kind isn't yet supported by `--apply` (method,
  /// enumValue, field). The user gets a notice and the entry is
  /// untouched.
  unsupportedKind,

  /// File was under `test/` or `integration_test/` and `--include-tests`
  /// was not passed. The entry was filtered out before deletion.
  skippedTest,

  /// AST traversal failed to find the declaration (file changed
  /// between detect and apply, or the line/name doesn't match any
  /// top-level declaration). User gets a stderr warning and the
  /// entry is untouched.
  notFound,
}

/// Per-entry record produced by [applyDeletions].
class ApplyResult {
  ApplyResult({required this.outcome});

  final ApplyOutcome outcome;
}

/// Top-level kinds that this v1 of `--apply` can delete from source.
/// Others (`method`, `enumValue`, `field`) need range computation
/// relative to a containing declaration which we defer.
const _supportedKinds = {
  UnusedKind.function,
  UnusedKind.klass,
  UnusedKind.typedef,
  UnusedKind.extension,
};

/// Deletes every declaration in [targets] from disk. Returns one
/// [ApplyResult] per input. Callers should print a summary.
///
/// Filters:
/// - Files under `test/` or `integration_test/` are excluded unless
///   [includeTests] is true.
/// - Unsupported kinds emit `ApplyOutcome.unsupportedKind` without
///   touching the file.
///
/// Range computation: each top-level declaration is identified by
/// `(file, name, line)` against the freshly-parsed file. The deletion
/// range starts at the *first* of (declaration offset, leading doc
/// comment offset, first metadata annotation offset) and extends to
/// the end of the declaration plus a trailing newline if present, so
/// the file doesn't end up with a row of blank lines where the
/// declaration used to be.
///
/// Multiple declarations from the same file are deleted in *descending
/// offset order* so each deletion doesn't shift offsets the next one
/// expects.
List<ApplyResult> applyDeletions(
  List<UnusedDeclaration> targets, {
  required bool includeTests,
}) {
  final results = <ApplyResult>[];
  final byFile = _partitionTargets(
    targets,
    includeTests: includeTests,
    results: results,
  );
  for (final entry in byFile.entries) {
    _processFile(entry.key, entry.value, results);
  }
  return results;
}

/// Splits [targets] into the per-file delete pile plus immediately
/// adds `unsupportedKind` / `skippedTest` outcomes to [results] for
/// targets that never reach the AST pass.
Map<String, List<UnusedDeclaration>> _partitionTargets(
  List<UnusedDeclaration> targets, {
  required bool includeTests,
  required List<ApplyResult> results,
}) {
  final byFile = <String, List<UnusedDeclaration>>{};
  for (final t in targets) {
    if (!_supportedKinds.contains(t.kind)) {
      results.add(ApplyResult(outcome: ApplyOutcome.unsupportedKind));
      continue;
    }
    if (!includeTests && _isTestPath(t.location.path)) {
      results.add(ApplyResult(outcome: ApplyOutcome.skippedTest));
      continue;
    }
    byFile.putIfAbsent(t.location.path, () => <UnusedDeclaration>[]).add(t);
  }
  return byFile;
}

/// Parses [path] once, walks each [fileTargets] entry to its AST node,
/// then deletes the resolved ranges in descending offset order so
/// earlier deletions don't shift later ones.
void _processFile(
  String path,
  List<UnusedDeclaration> fileTargets,
  List<ApplyResult> results,
) {
  final source = File(path).readAsStringSync();
  final unit = parseString(content: source).unit;

  final ranges = <_DeleteRange>[];
  for (final t in fileTargets) {
    final node = _findTopLevel(unit, t.name, t.location.line);
    if (node == null) {
      results.add(ApplyResult(outcome: ApplyOutcome.notFound));
      continue;
    }
    ranges.add(_DeleteRange(range: _rangeFor(node, source)));
  }
  if (ranges.isEmpty) return;

  ranges.sort((a, b) => b.range.start.compareTo(a.range.start));
  var rewritten = source;
  for (final r in ranges) {
    rewritten = rewritten.replaceRange(r.range.start, r.range.end, '');
    results.add(ApplyResult(outcome: ApplyOutcome.deleted));
  }
  File(path).writeAsStringSync(rewritten);
}

/// `git status --porcelain` returns a non-empty body when there is any
/// staged or unstaged change. The `--apply` flow refuses to run on a
/// dirty tree so the user can `git diff` the deletions afterwards.
/// Returns `true` when the tree is clean **or** when [root] is not a
/// git repository at all (`git` exits non-zero and we treat the
/// directory as ungated). On a host where the `git` binary is
/// genuinely missing, this throws `ProcessException`; the user can
/// pass `--force` on the CLI to skip the check entirely.
bool isGitTreeClean(String root) {
  final r = Process.runSync('git', [
    'status',
    '--porcelain',
  ], workingDirectory: root);
  if (r.exitCode != 0) return true; // not a git repo
  return (r.stdout as String).trim().isEmpty;
}

bool _isTestPath(String path) {
  final segments = path.replaceAll('\\', '/').split('/');
  return segments.contains('test') || segments.contains('integration_test');
}

/// Walks top-level [unit] declarations for a node whose declared name
/// matches [name]. [line] is unused — top-level Dart names are unique
/// within a compilation unit, so the name match is sufficient. Line is
/// kept on [UnusedDeclaration] as a hint for the human-facing reporter.
AstNode? _findTopLevel(CompilationUnit unit, String name, int line) {
  for (final d in unit.declarations) {
    if (_declarationName(d) == name) return d;
  }
  return null;
}

/// Returns the declared simple-name for the top-level declaration kinds
/// `--apply` knows how to delete, or `null` for kinds it does not. The
/// caller does the equality check against the target's name; isolating
/// the name accessor here keeps the per-kind branches out of the
/// reachability lookup.
String? _declarationName(CompilationUnitMember d) {
  if (d is FunctionDeclaration) return d.name.lexeme;
  if (d is ClassDeclaration) return d.namePart.typeName.lexeme;
  if (d is GenericTypeAlias) return d.name.lexeme;
  if (d is FunctionTypeAlias) return d.name.lexeme;
  if (d is ExtensionDeclaration) return d.name?.lexeme;
  return null;
}

/// Computes the [start, end) byte range covering a declaration plus
/// its leading doc comment, leading metadata annotations, and a
/// trailing newline so the file doesn't keep an empty line where the
/// declaration used to be.
///
/// The range intentionally **does not** consume blank lines preceding
/// the declaration — those are usually structural separators between
/// neighbouring declarations and trying to be smart about them risks
/// producing a denser-than-intended file. The user can run
/// `dart format` after `--apply` if they want to normalise.
({int start, int end}) _rangeFor(AstNode node, String source) {
  return (start: _leadingStart(node), end: _trailingEnd(node.end, source));
}

/// Earliest offset that "belongs to" [node] for deletion purposes:
/// the declaration's own offset, or — if [node] is annotated — the
/// minimum across the doc comment and every metadata annotation.
int _leadingStart(AstNode node) {
  var start = node.offset;
  if (node is! AnnotatedNode) return start;
  final doc = node.documentationComment;
  if (doc != null && doc.offset < start) start = doc.offset;
  for (final meta in node.metadata) {
    if (meta.offset < start) start = meta.offset;
  }
  return start;
}

/// Extends [end] forward through trailing horizontal whitespace and at
/// most one newline so the file doesn't keep an empty line where the
/// declaration's closing token used to sit.
int _trailingEnd(int end, String source) {
  while (end < source.length && (source[end] == ' ' || source[end] == '\t')) {
    end++;
  }
  if (end < source.length && source[end] == '\n') end++;
  return end;
}

class _DeleteRange {
  _DeleteRange({required this.range});
  final ({int start, int end}) range;
}
