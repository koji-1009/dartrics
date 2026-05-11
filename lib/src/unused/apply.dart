import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../models/unused_declaration.dart';

/// Outcome of one declaration's deletion attempt.
enum ApplyOutcome {
  /// Declaration's source range was deleted from the file.
  deleted,

  /// Declaration kind isn't deletable (e.g. the only constant in an
  /// enum, where removal would leave invalid Dart). The user gets a
  /// notice and the entry is untouched.
  unsupportedKind,

  /// File was under `test/` or `integration_test/` and `--include-tests`
  /// was not passed. The entry was filtered out before deletion.
  skippedTest,

  /// AST traversal failed to find the declaration (file changed
  /// between detect and apply, or the line/name doesn't match any
  /// declaration). User gets a stderr warning and the entry is
  /// untouched.
  notFound,

  /// Field is named in a `this.<field>` initializing formal of some
  /// constructor on the enclosing class. Deleting the field alone
  /// would leave a dangling formal and break compilation, and
  /// rewriting the formal + every named-argument call site is out of
  /// scope for `--apply` (auto-rewriting callers is the kind of change
  /// the user wants to author explicitly). The entry is left
  /// untouched and reported.
  coupledConstructorFormal,
}

/// Per-entry record produced by [applyDeletions].
class ApplyResult {
  ApplyResult({required this.outcome, this.detail});

  final ApplyOutcome outcome;

  /// Optional structured per-entry context for the CLI summary layer.
  /// Currently populated for [ApplyOutcome.coupledConstructorFormal]
  /// so the summary can name the affected `(file, class, field)` and
  /// the constructor(s) that reference it.
  final ApplyResultDetail? detail;
}

/// Per-entry context attached to an [ApplyResult]. Lives in the apply
/// module so the CLI summary can render an outcome without re-walking
/// the source.
class ApplyResultDetail {
  ApplyResultDetail({
    required this.file,
    required this.line,
    required this.name,
    this.coupledConstructors = const [],
  });

  final String file;
  final int line;
  final String name;

  /// Qualified constructor names (`Class` for the unnamed default,
  /// `Class.named` otherwise) that reference the field as a
  /// `this.<name>` initializing formal. Empty for outcomes other than
  /// [ApplyOutcome.coupledConstructorFormal].
  final List<String> coupledConstructors;
}

/// Deletes every declaration in [targets] from disk. Returns one
/// [ApplyResult] per input. Callers should print a summary.
///
/// Supports every [UnusedKind] the resolved-AST detector emits:
/// top-level functions / classes / mixins / extensions / extension
/// types / enums / typedefs, instance methods (incl. operators,
/// getters, setters), instance fields and top-level variables (both
/// single-variable and one-of-N in multi-variable declarations), and
/// individual enum constants.
///
/// Filters:
/// - Files under `test/` or `integration_test/` are excluded unless
///   [includeTests] is true.
/// - Targets that would leave invalid Dart (e.g. removing the only
///   constant in an enum) emit `ApplyOutcome.unsupportedKind`
///   without touching the file.
///
/// Range computation: each declaration is identified by `(file, name,
/// line)` against the freshly-parsed file. The deletion range starts
/// at the *first* of (declaration offset, leading doc comment offset,
/// first metadata annotation offset) and extends to the end of the
/// declaration plus a trailing newline if present, so the file
/// doesn't end up with a row of blank lines where the declaration
/// used to be. For a member of a comma-separated list (one variable
/// in `int x, y, z;`, one constant in `enum E { a, b, c }`), the
/// range covers the member and the comma that joins it to the
/// surviving siblings, so the resulting list stays well-formed.
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
/// adds `skippedTest` outcomes to [results] for targets that never
/// reach the AST pass.
Map<String, List<UnusedDeclaration>> _partitionTargets(
  List<UnusedDeclaration> targets, {
  required bool includeTests,
  required List<ApplyResult> results,
}) {
  final byFile = <String, List<UnusedDeclaration>>{};
  for (final t in targets) {
    if (!includeTests && _isTestPath(t.location.path)) {
      results.add(ApplyResult(outcome: ApplyOutcome.skippedTest));
      continue;
    }
    byFile.putIfAbsent(t.location.path, () => <UnusedDeclaration>[]).add(t);
  }
  return byFile;
}

/// Parses [path] once, walks each [fileTargets] entry to its byte
/// range, merges nested / overlapping ranges (so deleting a class
/// alongside its members doesn't double-delete or crash on shifted
/// offsets), then applies the merged ranges in descending offset
/// order. Each input target still gets exactly one [ApplyResult] —
/// targets whose range was subsumed by an outer range still report
/// `deleted` because the source no longer contains them.
void _processFile(
  String path,
  List<UnusedDeclaration> fileTargets,
  List<ApplyResult> results,
) {
  final source = File(path).readAsStringSync();
  final unit = parseString(content: source).unit;

  final ranges = <({int start, int end})>[];
  for (final t in fileTargets) {
    final resolved = _resolveDeletionRange(
      unit: unit,
      target: t,
      source: source,
    );
    switch (resolved) {
      case _Resolved(:final range):
        ranges.add(range);
        results.add(ApplyResult(outcome: ApplyOutcome.deleted));
      case _Unsupported():
        results.add(ApplyResult(outcome: ApplyOutcome.unsupportedKind));
      case _NotFound():
        results.add(ApplyResult(outcome: ApplyOutcome.notFound));
      case _Coupled(:final constructorNames):
        results.add(
          ApplyResult(
            outcome: ApplyOutcome.coupledConstructorFormal,
            detail: ApplyResultDetail(
              file: t.location.path,
              line: t.location.line,
              name: t.name,
              coupledConstructors: constructorNames,
            ),
          ),
        );
    }
  }
  if (ranges.isEmpty) return;

  final merged = _mergeRanges(ranges);
  merged.sort((a, b) => b.start.compareTo(a.start));
  var rewritten = source;
  for (final r in merged) {
    rewritten = rewritten.replaceRange(r.start, r.end, '');
  }
  File(path).writeAsStringSync(rewritten);
}

/// Coalesces overlapping / nested ranges. After merging, the returned
/// list is non-overlapping in source order — a class's range subsumes
/// every member range it contains, so applying the merged list once
/// matches the desired "everything inside the outer slice goes" shape
/// without each replaceRange call having to know about its siblings.
List<({int start, int end})> _mergeRanges(List<({int start, int end})> input) {
  if (input.isEmpty) return input;
  final sorted = [...input]..sort((a, b) => a.start.compareTo(b.start));
  final out = <({int start, int end})>[];
  var current = sorted.first;
  for (var i = 1; i < sorted.length; i++) {
    final next = sorted[i];
    if (next.start < current.end) {
      if (next.end > current.end) {
        current = (start: current.start, end: next.end);
      }
    } else {
      out.add(current);
      current = next;
    }
  }
  out.add(current);
  return out;
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

sealed class _LocatorResult {
  const _LocatorResult();
}

class _Resolved extends _LocatorResult {
  const _Resolved(this.range);
  final ({int start, int end}) range;
}

class _NotFound extends _LocatorResult {
  const _NotFound();
}

class _Unsupported extends _LocatorResult {
  const _Unsupported();
}

class _Coupled extends _LocatorResult {
  const _Coupled({required this.constructorNames});

  /// Qualified constructor names that reference the would-be-deleted
  /// field as `this.<name>` initializing formal. Used by the CLI
  /// summary so the user can find and edit them by hand.
  final List<String> constructorNames;
}

/// Per-kind dispatch that returns a deletion range, an unsupported
/// marker (e.g. the only constant in an enum), or a notFound marker
/// (the source has shifted since detection).
_LocatorResult _resolveDeletionRange({
  required CompilationUnit unit,
  required UnusedDeclaration target,
  required String source,
}) {
  return switch (target.kind) {
    UnusedKind.function ||
    UnusedKind.klass ||
    UnusedKind.typedef ||
    UnusedKind.extension => _resolveTopLevel(unit, target.name, source),
    UnusedKind.method => _resolveMethod(
      unit: unit,
      name: target.name,
      line: target.location.line,
      source: source,
    ),
    UnusedKind.field => _resolveField(
      unit: unit,
      name: target.name,
      line: target.location.line,
      source: source,
    ),
    UnusedKind.enumValue => _resolveEnumValue(
      unit: unit,
      name: target.name,
      line: target.location.line,
      source: source,
    ),
  };
}

_LocatorResult _resolveTopLevel(
  CompilationUnit unit,
  String name,
  String source,
) {
  for (final d in unit.declarations) {
    if (_topLevelDeclarationName(d) == name) {
      return _Resolved(_rangeFor(d, source));
    }
  }
  return const _NotFound();
}

/// Returns the declared simple-name for the top-level declaration kinds
/// `--apply` treats as whole-node deletions, or `null` for kinds it
/// does not.
String? _topLevelDeclarationName(CompilationUnitMember d) {
  if (d is FunctionDeclaration) return d.name.lexeme;
  if (d is ClassDeclaration) return d.namePart.typeName.lexeme;
  if (d is MixinDeclaration) return d.name.lexeme;
  if (d is EnumDeclaration) return d.namePart.typeName.lexeme;
  if (d is ExtensionTypeDeclaration) {
    return d.primaryConstructor.typeName.lexeme;
  }
  if (d is GenericTypeAlias) return d.name.lexeme;
  if (d is FunctionTypeAlias) return d.name.lexeme;
  if (d is ExtensionDeclaration) return d.name?.lexeme;
  return null;
}

_LocatorResult _resolveMethod({
  required CompilationUnit unit,
  required String name,
  required int line,
  required String source,
}) {
  final lineInfo = unit.lineInfo;
  for (final member in _classLikeMembers(unit)) {
    if (member is! MethodDeclaration) continue;
    if (member.name.lexeme != name) continue;
    if (lineInfo.getLocation(member.offset).lineNumber != line) continue;
    return _Resolved(_rangeFor(member, source));
  }
  return const _NotFound();
}

_LocatorResult _resolveField({
  required CompilationUnit unit,
  required String name,
  required int line,
  required String source,
}) {
  final topLevel = _resolveTopLevelField(
    unit: unit,
    name: name,
    line: line,
    source: source,
  );
  if (topLevel is! _NotFound) return topLevel;
  return _resolveInstanceField(
    unit: unit,
    name: name,
    line: line,
    source: source,
  );
}

_LocatorResult _resolveTopLevelField({
  required CompilationUnit unit,
  required String name,
  required int line,
  required String source,
}) {
  final lineInfo = unit.lineInfo;
  for (final d in unit.declarations) {
    if (d is! TopLevelVariableDeclaration) continue;
    final hit = _resolveVariableInList(
      list: d.variables,
      name: name,
      line: line,
      lineInfo: lineInfo,
    );
    if (hit == null) continue;
    return _Resolved(
      _rangeForVariable(
        parentDeclaration: d,
        list: d.variables,
        target: hit,
        source: source,
      ),
    );
  }
  return const _NotFound();
}

/// Walks each class-like container once so the same container's
/// constructors can be inspected for a `this.<name>` initializing
/// formal before the field's deletion range is committed.
_LocatorResult _resolveInstanceField({
  required CompilationUnit unit,
  required String name,
  required int line,
  required String source,
}) {
  final lineInfo = unit.lineInfo;
  for (final d in unit.declarations) {
    final body = _classLikeBody(d);
    if (body == null) continue;
    final result = _resolveInstanceFieldInBody(
      container: d,
      body: body,
      name: name,
      line: line,
      lineInfo: lineInfo,
      source: source,
    );
    if (result is! _NotFound) return result;
  }
  return const _NotFound();
}

_LocatorResult _resolveInstanceFieldInBody({
  required CompilationUnitMember container,
  required NodeList<ClassMember> body,
  required String name,
  required int line,
  required LineInfo lineInfo,
  required String source,
}) {
  for (final member in body) {
    if (member is! FieldDeclaration) continue;
    final hit = _resolveVariableInList(
      list: member.fields,
      name: name,
      line: line,
      lineInfo: lineInfo,
    );
    if (hit == null) continue;
    final coupledCtors = _constructorsReferencingFormal(
      container: container,
      body: body,
      fieldName: name,
    );
    if (coupledCtors.isNotEmpty) {
      return _Coupled(constructorNames: coupledCtors);
    }
    return _Resolved(
      _rangeForVariable(
        parentDeclaration: member,
        list: member.fields,
        target: hit,
        source: source,
      ),
    );
  }
  return const _NotFound();
}

/// Returns the qualified names of every constructor in [body] that
/// references [fieldName] as a `this.<name>` initializing formal.
/// Empty list means the field is safe to delete on its own. Pure
/// syntactic — `this.<name>` is unambiguous Dart for "initialize the
/// enclosing class's field named `<name>`".
List<String> _constructorsReferencingFormal({
  required CompilationUnitMember container,
  required NodeList<ClassMember> body,
  required String fieldName,
}) {
  // Containers reachable here always have a name (class / enum /
  // extension type / mixin / extension). Mixins and extensions can't
  // declare constructors, so the loop below filters them out before
  // this label is materialised; if a future grammar lets one slip
  // through unnamed, the `?` fallback keeps the report rendering.
  final containerName = _topLevelDeclarationName(container) ?? '?';
  final out = <String>[];
  for (final m in body) {
    if (m is! ConstructorDeclaration) continue;
    final hasFormal = m.parameters.parameters.any(
      (p) => _fieldFormalNameMatches(p, fieldName),
    );
    if (!hasFormal) continue;
    final ctorName = m.name?.lexeme;
    out.add(ctorName == null ? containerName : '$containerName.$ctorName');
  }
  return out;
}

/// True when [p] is a `this.<fieldName>` initializing formal. Modern
/// analyzer keeps `FieldFormalParameter` first-class (any default
/// value lives on a sibling `defaultClause`), so there is no wrapper
/// node to unbox.
bool _fieldFormalNameMatches(FormalParameter p, String fieldName) {
  return p is FieldFormalParameter && p.name.lexeme == fieldName;
}

VariableDeclaration? _resolveVariableInList({
  required VariableDeclarationList list,
  required String name,
  required int line,
  required LineInfo lineInfo,
}) {
  for (final v in list.variables) {
    if (v.name.lexeme != name) continue;
    if (lineInfo.getLocation(v.offset).lineNumber != line) continue;
    return v;
  }
  return null;
}

_LocatorResult _resolveEnumValue({
  required CompilationUnit unit,
  required String name,
  required int line,
  required String source,
}) {
  final lineInfo = unit.lineInfo;
  for (final d in unit.declarations) {
    if (d is! EnumDeclaration) continue;
    final constants = d.body.constants;
    for (var i = 0; i < constants.length; i++) {
      final c = constants[i];
      if (c.name.lexeme != name) continue;
      if (lineInfo.getLocation(c.offset).lineNumber != line) continue;
      if (constants.length == 1) {
        // Removing the only constant would leave invalid Dart; punt.
        return const _Unsupported();
      }
      return _Resolved(_rangeForEnumConstant(constants, i));
    }
  }
  return const _NotFound();
}

/// Walks every class-like compilation-unit member's body and yields
/// each [ClassMember]. Covers `ClassDeclaration`, `MixinDeclaration`,
/// `ExtensionDeclaration`, `ExtensionTypeDeclaration`, and
/// `EnumDeclaration` so the same locator handles instance methods /
/// fields anywhere they can appear.
Iterable<ClassMember> _classLikeMembers(CompilationUnit unit) sync* {
  for (final d in unit.declarations) {
    final body = _classLikeBody(d);
    if (body == null) continue;
    yield* body;
  }
}

NodeList<ClassMember>? _classLikeBody(CompilationUnitMember d) {
  if (d is ClassDeclaration) return d.body.members;
  if (d is MixinDeclaration) return d.body.members;
  if (d is ExtensionDeclaration) return d.body.members;
  if (d is ExtensionTypeDeclaration) return d.body.members;
  if (d is EnumDeclaration) return d.body.members;
  return null;
}

/// Computes the [start, end) byte range covering a declaration plus
/// its leading doc comment, leading metadata annotations, the same-line
/// indent in front of the declaration, and a trailing newline so the
/// file doesn't keep an empty line nor a doubled indent where the
/// declaration used to be.
({int start, int end}) _rangeFor(AstNode node, String source) {
  var start = _leadingStart(node);
  // Back up through same-line leading whitespace so the deleted
  // physical line doesn't leak its indent onto the next line. Stops
  // at a `\n` (without crossing it) or at position 0; non-whitespace
  // earlier on the same line (a `}` etc.) halts the walk so we don't
  // chew into siblings.
  while (start > 0 && (source[start - 1] == ' ' || source[start - 1] == '\t')) {
    start--;
  }
  return (start: start, end: _trailingEnd(node.end, source));
}

/// Range for one variable inside a [VariableDeclarationList].
///
/// - Single-variable list: the whole parent declaration is removed
///   (same shape as a top-level deletion).
/// - First / middle variable: the slice from the variable's start to
///   the next variable's start. This swallows the comma separator
///   between this variable and the next.
/// - Last variable: the slice from the previous variable's end to
///   this variable's end. This swallows the comma separator that
///   joined the previous variable to this one.
({int start, int end}) _rangeForVariable({
  required AstNode parentDeclaration,
  required VariableDeclarationList list,
  required VariableDeclaration target,
  required String source,
}) {
  if (list.variables.length == 1) {
    return _rangeFor(parentDeclaration, source);
  }
  final index = list.variables.indexOf(target);
  if (index < list.variables.length - 1) {
    final next = list.variables[index + 1];
    return (start: target.offset, end: next.offset);
  }
  final prev = list.variables[index - 1];
  return (start: prev.end, end: target.end);
}

/// Range for one constant in a non-singleton [EnumDeclaration]
/// constants list. Same comma-aware logic as [_rangeForVariable] but
/// applied to [EnumConstantDeclaration] siblings — the enum body's
/// trailing `;` separator (when present) and any nested members are
/// outside the deleted slice.
({int start, int end}) _rangeForEnumConstant(
  NodeList<EnumConstantDeclaration> constants,
  int index,
) {
  final target = constants[index];
  if (index < constants.length - 1) {
    final next = constants[index + 1];
    return (start: _leadingStart(target), end: _leadingStart(next));
  }
  final prev = constants[index - 1];
  return (start: prev.end, end: target.end);
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
