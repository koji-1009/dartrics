import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/line_info.dart';

import '../config/config.dart';
import '../models/source_location.dart';
import '../models/unused_declaration.dart';
import 'declaration_record.dart';
import 'keep_alive_presets.dart';

/// Input record accepted by [detectUnusedResolved] — a single fully-resolved
/// Dart source file.
typedef ResolvedUnusedSource = ({String path, ResolvedUnitResult unit});

/// Method names called by the language runtime / framework rather than
/// from user source. Auto-rooted so the detector doesn't false-positive
/// on overrides whose only "caller" is the platform.
const _objectDunderNames = {
  'toString',
  'hashCode',
  '==',
  'noSuchMethod',
  'runtimeType',
};

/// Element-resolution-based unused-declaration detection.
///
/// The reachability graph is keyed on canonical [Element.id]s of declared
/// elements (top-level + class / mixin / extension / extension-type
/// members + enum values). References are resolved via analyzer's static
/// element model, not simple-name match — so homonym methods on
/// different classes are independent nodes, prefixed imports keep
/// distinct identities, and SDK / dependency symbols never accidentally
/// keep project declarations alive.
///
/// Granularity is finer than the parse-only `UnusedDetector.detect` path:
/// methods, fields, getters, setters, and enum values are tracked
/// individually so the report can highlight a single unused member
/// without the user needing to delete the whole class. Use the `filter`
/// field on [UnusedConfig] (or `--filter` on the CLI) to narrow the
/// kinds emitted.
List<UnusedDeclaration> detectUnusedResolved(
  List<ResolvedUnusedSource> sources,
  UnusedConfig config,
) {
  final filterKinds = parseUnusedFilter(config.filter);
  final declarations = <_ResolvedDeclaration>[];
  for (final s in sources) {
    _collectFromUnit(s, declarations);
  }
  final byId = <int, _ResolvedDeclaration>{
    for (final d in declarations) d.elementId: d,
  };
  final roots = _resolveRoots(
    declarations: declarations,
    byId: byId,
    sources: sources,
    config: config,
  );
  final reachable = _bfs(roots, byId);
  final out = <UnusedDeclaration>[];
  for (final d in declarations) {
    if (d.record.name.startsWith('_')) continue;
    if (reachable.contains(d.elementId)) continue;
    if (filterKinds != null && !filterKinds.contains(d.record.kind)) continue;
    out.add(
      UnusedDeclaration(
        kind: d.record.kind,
        name: d.record.name,
        location: d.record.location,
      ),
    );
  }
  return out;
}

/// Translates the raw `filter` strings from [UnusedConfig] into a kind
/// set. Returns `null` when no filter is configured (= keep every kind).
/// Throws [FormatException] for unknown names so the caller (CLI /
/// config loader) can surface a usage error rather than silently
/// dropping every entry.
Set<UnusedKind>? parseUnusedFilter(List<String> filter) {
  if (filter.isEmpty) return null;
  final out = <UnusedKind>{};
  for (final raw in filter) {
    final name = raw.trim();
    if (name.isEmpty) continue;
    final match = _kindByName(name);
    if (match == null) {
      throw FormatException(
        'unused.filter: unknown kind "$raw". valid kinds: '
        '${UnusedKind.values.map((k) => k.name).join(", ")}',
      );
    }
    out.add(match);
  }
  return out.isEmpty ? null : out;
}

UnusedKind? _kindByName(String name) {
  for (final k in UnusedKind.values) {
    if (k.name == name) return k;
  }
  return null;
}

Set<int> _bfs(Iterable<int> roots, Map<int, _ResolvedDeclaration> byId) {
  final visited = <int>{};
  final queue = <int>[...roots];
  while (queue.isNotEmpty) {
    final id = queue.removeLast();
    if (!visited.add(id)) continue;
    final next = byId[id];
    if (next == null) continue;
    for (final outId in next.outgoingIds) {
      if (!visited.contains(outId)) queue.add(outId);
    }
  }
  return visited;
}

Set<int> _resolveRoots({
  required List<_ResolvedDeclaration> declarations,
  required Map<int, _ResolvedDeclaration> byId,
  required List<ResolvedUnusedSource> sources,
  required UnusedConfig config,
}) {
  final rc = _RootContext(
    entryNames: _buildEntryNames(config),
    keepAliveAnnotations: _buildKeepAliveAnnotations(config),
    exportedRoots: config.excludeExported
        ? _collectExportedRoots(sources, byId)
        : const <int>{},
    excludeExported: config.excludeExported,
  );
  final roots = <int>{};
  final annotationKeptTypeIds = <int>{};
  for (final d in declarations) {
    if (_isRoot(d, rc)) roots.add(d.elementId);
    if (_propagatesAnnotationKeepAlive(d, rc)) {
      annotationKeptTypeIds.add(d.elementId);
    }
  }
  _addAnnotationPropagatedRoots(declarations, annotationKeptTypeIds, roots);
  return roots;
}

Set<String> _buildEntryNames(UnusedConfig config) {
  final out = <String>{};
  for (final ep in config.entryPoints) {
    if (!ep.startsWith('@pragma:')) out.add(ep);
  }
  return out;
}

Set<String> _buildKeepAliveAnnotations(UnusedConfig config) => <String>{
  ...config.ignoreAnnotations,
  ...allKeepAliveAnnotations,
};

bool _isRoot(_ResolvedDeclaration d, _RootContext rc) {
  return _matchesEntryName(d, rc) ||
      d.record.hasVmEntryPointPragma ||
      _matchesKeepAliveAnnotation(d, rc) ||
      d.isOverride ||
      d.isObjectDunder ||
      _matchesLibPublicTopLevel(d, rc) ||
      rc.exportedRoots.contains(d.elementId);
}

/// Entry-point names (`main`, `test`, …) only match top-level
/// declarations — a class method named `main` is not a process entry
/// point.
bool _matchesEntryName(_ResolvedDeclaration d, _RootContext rc) =>
    rc.entryNames.contains(d.record.name) && !d.isInstanceMember;

bool _matchesKeepAliveAnnotation(_ResolvedDeclaration d, _RootContext rc) =>
    rc.keepAliveAnnotations.any(d.record.annotations.contains);

bool _matchesLibPublicTopLevel(_ResolvedDeclaration d, _RootContext rc) =>
    rc.excludeExported && d.isInLibPublic && !d.isInstanceMember;

/// Codegen / reflection markers attach to the class
/// (`@JsonSerializable`, `@reflectiveTest`, …); the actual "callers"
/// are the generator / runtime, which read every public member by
/// reflection. Returns `true` for top-level declarations whose
/// annotations should propagate keep-alive to their members.
bool _propagatesAnnotationKeepAlive(_ResolvedDeclaration d, _RootContext rc) =>
    !d.isInstanceMember && _matchesKeepAliveAnnotation(d, rc);

void _addAnnotationPropagatedRoots(
  List<_ResolvedDeclaration> declarations,
  Set<int> annotationKeptTypeIds,
  Set<int> roots,
) {
  if (annotationKeptTypeIds.isEmpty) return;
  for (final d in declarations) {
    final encl = d.enclosingTypeElementId;
    if (encl != null && annotationKeptTypeIds.contains(encl)) {
      roots.add(d.elementId);
    }
  }
}

class _RootContext {
  _RootContext({
    required this.entryNames,
    required this.keepAliveAnnotations,
    required this.exportedRoots,
    required this.excludeExported,
  });

  final Set<String> entryNames;
  final Set<String> keepAliveAnnotations;
  final Set<int> exportedRoots;
  final bool excludeExported;
}

/// Walks every public library (under `lib/` outside `lib/src/`) and
/// turns its export namespace into a set of project-local element ids.
/// For interface / extension elements it also pulls in every public
/// member so a re-exported class doesn't leak "unused" reports for its
/// methods that consumers can call.
Set<int> _collectExportedRoots(
  List<ResolvedUnusedSource> sources,
  Map<int, _ResolvedDeclaration> byId,
) {
  final out = <int>{};
  for (final s in sources) {
    if (!_isLibraryPublic(s.path)) continue;
    final library = s.unit.libraryElement;
    for (final element in library.exportNamespace.definedNames2.values) {
      _addExportedElement(element, byId, out);
    }
  }
  return out;
}

void _addExportedElement(
  Element element,
  Map<int, _ResolvedDeclaration> byId,
  Set<int> out,
) {
  final canonical = element.baseElement.nonSynthetic;
  if (byId.containsKey(canonical.id)) {
    out.add(canonical.id);
  }
  if (canonical is InstanceElement) {
    for (final m in canonical.methods) {
      _addIfTracked(m, byId, out);
    }
    for (final f in canonical.fields) {
      _addIfTracked(f, byId, out);
    }
    for (final g in canonical.getters) {
      _addIfTracked(g, byId, out);
    }
    for (final s in canonical.setters) {
      _addIfTracked(s, byId, out);
    }
  }
}

void _addIfTracked(
  Element element,
  Map<int, _ResolvedDeclaration> byId,
  Set<int> out,
) {
  final id = element.baseElement.nonSynthetic.id;
  if (byId.containsKey(id)) out.add(id);
}

bool _isLibraryPublic(String path) {
  final unix = path.replaceAll(r'\', '/');
  if (!unix.contains('/lib/')) return false;
  if (unix.contains('/lib/src/')) return false;
  return true;
}

void _collectFromUnit(
  ResolvedUnusedSource src,
  List<_ResolvedDeclaration> out,
) {
  final ctx = _CollectionContext(
    path: src.path,
    lineInfo: src.unit.lineInfo,
    isLibPublic: _isLibraryPublic(src.path),
  );
  for (final decl in src.unit.unit.declarations) {
    _collectDeclaration(decl, ctx, out);
  }
}

void _collectDeclaration(
  CompilationUnitMember decl,
  _CollectionContext ctx,
  List<_ResolvedDeclaration> out,
) {
  if (_collectTypeLikeDeclaration(decl, ctx, out)) return;
  _collectFlatDeclaration(decl, ctx, out);
}

/// Handles the four "container" declaration shapes (class / mixin /
/// extension / extension-type / enum). Returns `true` when [decl]
/// matched one of them.
bool _collectTypeLikeDeclaration(
  CompilationUnitMember decl,
  _CollectionContext ctx,
  List<_ResolvedDeclaration> out,
) {
  switch (decl) {
    case ClassDeclaration():
      _collectInterfaceLike(
        decl: decl,
        name: decl.namePart.typeName.lexeme,
        kind: UnusedKind.klass,
        members: decl.body.members,
        element: decl.declaredFragment?.element,
        ctx: ctx,
        out: out,
      );
    case MixinDeclaration():
      _collectInterfaceLike(
        decl: decl,
        name: decl.name.lexeme,
        kind: UnusedKind.klass,
        members: decl.body.members,
        element: decl.declaredFragment?.element,
        ctx: ctx,
        out: out,
      );
    case ExtensionDeclaration():
      _collectExtension(decl, ctx, out);
    case ExtensionTypeDeclaration():
      _collectInterfaceLike(
        decl: decl,
        name: decl.primaryConstructor.typeName.lexeme,
        kind: UnusedKind.klass,
        members: decl.body.members,
        element: decl.declaredFragment?.element,
        ctx: ctx,
        out: out,
      );
    case EnumDeclaration():
      _collectEnum(decl, ctx, out);
    case _:
      return false;
  }
  return true;
}

/// Handles top-level declarations that don't carry a body of members
/// (functions, top-level variables, typedefs).
void _collectFlatDeclaration(
  CompilationUnitMember decl,
  _CollectionContext ctx,
  List<_ResolvedDeclaration> out,
) {
  switch (decl) {
    case FunctionDeclaration():
      _emitTopLevelFunction(decl, ctx, out);
    case TopLevelVariableDeclaration():
      _emitTopLevelVariables(decl, ctx, out);
    case FunctionTypeAlias():
      _emitTypedefFromTypeAlias(
        decl: decl,
        element: decl.declaredFragment?.element,
        ctx: ctx,
        out: out,
      );
    case GenericTypeAlias():
      _emitTypedefFromTypeAlias(
        decl: decl,
        element: decl.declaredFragment?.element,
        ctx: ctx,
        out: out,
      );
    case _:
      break;
  }
}

void _emitTypedefFromTypeAlias({
  required TypeAlias decl,
  required Element? element,
  required _CollectionContext ctx,
  required List<_ResolvedDeclaration> out,
}) => _emitTypedef(
  node: decl,
  nameLexeme: decl.name.lexeme,
  offset: decl.offset,
  annotations: decl.metadata,
  element: element,
  ctx: ctx,
  out: out,
);

void _collectInterfaceLike({
  required CompilationUnitMember decl,
  required String name,
  required UnusedKind kind,
  required NodeList<ClassMember> members,
  required Element? element,
  required _CollectionContext ctx,
  required List<_ResolvedDeclaration> out,
}) {
  if (element == null) return;
  out.add(
    _ResolvedDeclaration(
      elementId: element.id,
      record: DeclarationRecord(
        name: name,
        kind: kind,
        location: ctx.locOf(decl.offset),
        outgoingNames: const {},
        annotations: decl.metadata.map((a) => a.name.name).toList(),
        hasVmEntryPointPragma: decl.metadata.any(_isVmEntryPointPragma),
      ),
      outgoingIds: _classOutgoing(decl, members, element.id),
      isInLibPublic: ctx.isLibPublic,
      isInstanceMember: false,
      isOverride: false,
      isObjectDunder: false,
    ),
  );
  for (final m in members) {
    _collectMember(m, ctx: ctx, out: out, enclosingTypeId: element.id);
  }
}

/// Outgoing edges for a class-like declaration:
/// - the type-level surface (annotations, supertypes, generics) — via
///   the outer walker that skips member declarations,
/// - every constructor body's references — folded in here because
///   constructors aren't separately tracked, so any code they touch
///   must be attributed to the class itself.
Set<int> _classOutgoing(
  CompilationUnitMember decl,
  NodeList<ClassMember> members,
  int ownElementId,
) {
  final out = _collectOutgoingExcludingMembers(
    decl,
    ownElementId: ownElementId,
  );
  for (final m in members) {
    if (m is ConstructorDeclaration) {
      out.addAll(_collectOutgoing(m, ownElementId: ownElementId));
    }
  }
  return out;
}

void _collectExtension(
  ExtensionDeclaration decl,
  _CollectionContext ctx,
  List<_ResolvedDeclaration> out,
) {
  final element = decl.declaredFragment?.element;
  if (element == null) return;
  final nameToken = decl.name;
  if (nameToken == null) {
    // Unnamed extension — there's nothing the user could `import` and
    // call by name. Members still need member-level reachability so we
    // walk them; the extension node itself is not registered.
    for (final m in decl.body.members) {
      _collectMember(m, ctx: ctx, out: out, enclosingTypeId: element.id);
    }
    return;
  }
  out.add(
    _ResolvedDeclaration(
      elementId: element.id,
      record: DeclarationRecord(
        name: nameToken.lexeme,
        kind: UnusedKind.extension,
        location: ctx.locOf(decl.offset),
        outgoingNames: const {},
        annotations: decl.metadata.map((a) => a.name.name).toList(),
        hasVmEntryPointPragma: decl.metadata.any(_isVmEntryPointPragma),
      ),
      outgoingIds: _classOutgoing(decl, decl.body.members, element.id),
      isInLibPublic: ctx.isLibPublic,
      isInstanceMember: false,
      isOverride: false,
      isObjectDunder: false,
    ),
  );
  for (final m in decl.body.members) {
    _collectMember(m, ctx: ctx, out: out, enclosingTypeId: element.id);
  }
}

void _collectEnum(
  EnumDeclaration decl,
  _CollectionContext ctx,
  List<_ResolvedDeclaration> out,
) {
  final element = decl.declaredFragment?.element;
  if (element == null) return;
  out.add(
    _ResolvedDeclaration(
      elementId: element.id,
      record: DeclarationRecord(
        name: decl.namePart.typeName.lexeme,
        kind: UnusedKind.klass,
        location: ctx.locOf(decl.offset),
        outgoingNames: const {},
        annotations: decl.metadata.map((a) => a.name.name).toList(),
        hasVmEntryPointPragma: decl.metadata.any(_isVmEntryPointPragma),
      ),
      outgoingIds: _classOutgoing(decl, decl.body.members, element.id),
      isInLibPublic: ctx.isLibPublic,
      isInstanceMember: false,
      isOverride: false,
      isObjectDunder: false,
    ),
  );
  for (final c in decl.body.constants) {
    final cElement = c.declaredFragment?.element;
    if (cElement == null) continue;
    out.add(
      _ResolvedDeclaration(
        elementId: cElement.id,
        record: DeclarationRecord(
          name: c.name.lexeme,
          kind: UnusedKind.enumValue,
          location: ctx.locOf(c.offset),
          outgoingNames: const {},
          annotations: c.metadata.map((a) => a.name.name).toList(),
          hasVmEntryPointPragma: c.metadata.any(_isVmEntryPointPragma),
        ),
        outgoingIds: _collectOutgoing(c, ownElementId: cElement.id),
        isInLibPublic: ctx.isLibPublic,
        isInstanceMember: true,
        isOverride: false,
        isObjectDunder: false,
        enclosingTypeElementId: element.id,
      ),
    );
  }
  for (final m in decl.body.members) {
    _collectMember(m, ctx: ctx, out: out, enclosingTypeId: element.id);
  }
}

void _collectMember(
  ClassMember member, {
  required _CollectionContext ctx,
  required List<_ResolvedDeclaration> out,
  required int enclosingTypeId,
}) {
  switch (member) {
    case MethodDeclaration():
      _emitMethod(member, ctx: ctx, out: out, enclosingTypeId: enclosingTypeId);
    case FieldDeclaration():
      _emitFields(member, ctx: ctx, out: out, enclosingTypeId: enclosingTypeId);
    case _:
      // ConstructorDeclaration / PrimaryConstructorBody — constructors
      // fold into the class's reachability, since a class being
      // reachable already implies at least one constructor is reachable
      // via the call site that reached it. Tracking each constructor
      // individually would surface "named constructor never called"
      // false-positives on idiomatic factory chains without a clear
      // refactor.
      break;
  }
}

void _emitMethod(
  MethodDeclaration decl, {
  required _CollectionContext ctx,
  required List<_ResolvedDeclaration> out,
  required int enclosingTypeId,
}) {
  final fragment = decl.declaredFragment;
  if (fragment == null) return;
  final element = fragment.element;
  final canonical = element.baseElement.nonSynthetic;
  final id = canonical.id;
  final name = decl.name.lexeme;
  if (name.isEmpty) return;
  final isOverride = decl.metadata.any((a) => a.name.name == 'override');
  final isObjectDunder = _objectDunderNames.contains(name);
  out.add(
    _ResolvedDeclaration(
      elementId: id,
      record: DeclarationRecord(
        name: name,
        kind: UnusedKind.method,
        location: ctx.locOf(decl.offset),
        outgoingNames: const {},
        annotations: decl.metadata.map((a) => a.name.name).toList(),
        hasVmEntryPointPragma: decl.metadata.any(_isVmEntryPointPragma),
      ),
      outgoingIds: _collectOutgoing(decl, ownElementId: id),
      isInLibPublic: ctx.isLibPublic,
      isInstanceMember: true,
      isOverride: isOverride,
      isObjectDunder: isObjectDunder,
      enclosingTypeElementId: enclosingTypeId,
    ),
  );
}

void _emitFields(
  FieldDeclaration decl, {
  required _CollectionContext ctx,
  required List<_ResolvedDeclaration> out,
  required int enclosingTypeId,
}) {
  final isOverride = decl.metadata.any((a) => a.name.name == 'override');
  final annotations = decl.metadata.map((a) => a.name.name).toList();
  final hasVmPragma = decl.metadata.any(_isVmEntryPointPragma);
  for (final v in decl.fields.variables) {
    final fragment = v.declaredFragment;
    if (fragment == null) continue;
    final canonical = fragment.element.baseElement.nonSynthetic;
    out.add(
      _ResolvedDeclaration(
        elementId: canonical.id,
        record: DeclarationRecord(
          name: v.name.lexeme,
          kind: UnusedKind.field,
          location: ctx.locOf(v.offset),
          outgoingNames: const {},
          annotations: annotations,
          hasVmEntryPointPragma: hasVmPragma,
        ),
        outgoingIds: _collectVariableOutgoing(
          variable: v,
          sharedType: decl.fields.type,
          metadata: decl.metadata,
          ownElementId: canonical.id,
        ),
        isInLibPublic: ctx.isLibPublic,
        isInstanceMember: true,
        isOverride: isOverride,
        isObjectDunder: false,
        enclosingTypeElementId: enclosingTypeId,
      ),
    );
  }
}

/// Outgoing-edge collection for a single variable inside a
/// [VariableDeclarationList]. The list-level shared type annotation and
/// the parent declaration's metadata sit on the parent, not on each
/// [VariableDeclaration], so per-variable emission has to walk them
/// explicitly to avoid losing edges (e.g. `final UnitContext x;` would
/// otherwise miss the reference to `UnitContext`).
Set<int> _collectVariableOutgoing({
  required VariableDeclaration variable,
  required TypeAnnotation? sharedType,
  required NodeList<Annotation> metadata,
  required int ownElementId,
}) {
  final out = <int>{};
  final visitor = _OutgoingCollector(out, ownElementId: ownElementId);
  variable.accept(visitor);
  sharedType?.accept(visitor);
  for (final annotation in metadata) {
    annotation.accept(visitor);
  }
  return out;
}

void _emitTopLevelFunction(
  FunctionDeclaration decl,
  _CollectionContext ctx,
  List<_ResolvedDeclaration> out,
) {
  final fragment = decl.declaredFragment;
  if (fragment == null) return;
  final canonical = fragment.element.baseElement.nonSynthetic;
  out.add(
    _ResolvedDeclaration(
      elementId: canonical.id,
      record: DeclarationRecord(
        name: decl.name.lexeme,
        kind: UnusedKind.function,
        location: ctx.locOf(decl.offset),
        outgoingNames: const {},
        annotations: decl.metadata.map((a) => a.name.name).toList(),
        hasVmEntryPointPragma: decl.metadata.any(_isVmEntryPointPragma),
      ),
      outgoingIds: _collectOutgoing(decl, ownElementId: canonical.id),
      isInLibPublic: ctx.isLibPublic,
      isInstanceMember: false,
      isOverride: false,
      isObjectDunder: false,
    ),
  );
}

void _emitTopLevelVariables(
  TopLevelVariableDeclaration decl,
  _CollectionContext ctx,
  List<_ResolvedDeclaration> out,
) {
  final annotations = decl.metadata.map((a) => a.name.name).toList();
  final hasVmPragma = decl.metadata.any(_isVmEntryPointPragma);
  for (final v in decl.variables.variables) {
    final fragment = v.declaredFragment;
    if (fragment == null) continue;
    final canonical = fragment.element.baseElement.nonSynthetic;
    out.add(
      _ResolvedDeclaration(
        elementId: canonical.id,
        record: DeclarationRecord(
          name: v.name.lexeme,
          kind: UnusedKind.field,
          location: ctx.locOf(v.offset),
          outgoingNames: const {},
          annotations: annotations,
          hasVmEntryPointPragma: hasVmPragma,
        ),
        outgoingIds: _collectVariableOutgoing(
          variable: v,
          sharedType: decl.variables.type,
          metadata: decl.metadata,
          ownElementId: canonical.id,
        ),
        isInLibPublic: ctx.isLibPublic,
        isInstanceMember: false,
        isOverride: false,
        isObjectDunder: false,
      ),
    );
  }
}

void _emitTypedef({
  required AstNode node,
  required String nameLexeme,
  required int offset,
  required NodeList<Annotation> annotations,
  required Element? element,
  required _CollectionContext ctx,
  required List<_ResolvedDeclaration> out,
}) {
  if (element == null) return;
  out.add(
    _ResolvedDeclaration(
      elementId: element.id,
      record: DeclarationRecord(
        name: nameLexeme,
        kind: UnusedKind.typedef,
        location: ctx.locOf(offset),
        outgoingNames: const {},
        annotations: annotations.map((a) => a.name.name).toList(),
        hasVmEntryPointPragma: annotations.any(_isVmEntryPointPragma),
      ),
      outgoingIds: _collectOutgoing(node, ownElementId: element.id),
      isInLibPublic: ctx.isLibPublic,
      isInstanceMember: false,
      isOverride: false,
      isObjectDunder: false,
    ),
  );
}

bool _isVmEntryPointPragma(Annotation ann) {
  if (ann.name.name != 'pragma') return false;
  final args = ann.arguments?.arguments ?? const [];
  if (args.isEmpty) return false;
  final first = args.first;
  return first is StringLiteral && first.stringValue == 'vm:entry-point';
}

Set<int> _collectOutgoing(AstNode node, {required int ownElementId}) {
  final out = <int>{};
  node.accept(_OutgoingCollector(out, ownElementId: ownElementId));
  return out;
}

/// Same as [_collectOutgoing] but skips descent into nested class
/// members. Used when walking the parts of a class / mixin /
/// extension / enum declaration that contribute the *type*'s own
/// outgoing edges (annotations, type parameters, extends / implements
/// / with clauses) — without double-counting the references that
/// each member already tracks on its own.
Set<int> _collectOutgoingExcludingMembers(
  AstNode node, {
  required int ownElementId,
}) {
  final out = <int>{};
  node.accept(_OuterOutgoingCollector(out, ownElementId: ownElementId));
  return out;
}

/// Walks an AST subtree and records every project-local element id it
/// references. References to off-project elements (SDK, dependencies)
/// land in the set as their own ids and are dropped during BFS because
/// they aren't keys in `byId`.
class _OutgoingCollector extends RecursiveAstVisitor<void> {
  _OutgoingCollector(this.out, {required this.ownElementId});

  final Set<int> out;
  final int ownElementId;

  void _record(Element? referent) {
    if (referent == null) return;
    var e = referent.baseElement.nonSynthetic;
    while (true) {
      if (e.id != ownElementId) {
        out.add(e.id);
      }
      final parent = e.enclosingElement;
      if (parent == null) return;
      if (parent is LibraryElement) return;
      e = parent.baseElement.nonSynthetic;
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    _record(node.element);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    _record(node.element);
    super.visitNamedType(node);
  }

  @override
  void visitAnnotation(Annotation node) {
    _record(node.element);
    super.visitAnnotation(node);
  }

  @override
  void visitConstructorReference(ConstructorReference node) {
    _record(node.constructorName.element);
    super.visitConstructorReference(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _record(node.constructorName.element);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _record(node.methodName.element);
    super.visitMethodInvocation(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    _record(node.propertyName.element);
    super.visitPropertyAccess(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    // For `target.field = value`, `propertyName.element` is left null
    // by the resolver — the setter (and, in compound assignments, the
    // getter) live on the assignment node itself.
    _record(node.writeElement);
    _record(node.readElement);
    super.visitAssignmentExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    // `x++` / `x--` writes back through a setter / variable just like
    // an assignment.
    _record(node.writeElement);
    _record(node.readElement);
    super.visitPostfixExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    // `++x` / `--x` — same as postfix.
    _record(node.writeElement);
    _record(node.readElement);
    super.visitPrefixExpression(node);
  }
}

/// Variant of [_OutgoingCollector] that does NOT descend into class
/// member declarations (methods, fields, constructors, enum
/// constants). The outer container's outgoing edge set is therefore
/// scoped to the type-level surface (annotations, supertypes,
/// generics) — every member declaration registers its own edges on a
/// separate node, so re-walking the body would double-count and, more
/// importantly, make the container's reachability transitively root
/// every member it owns.
class _OuterOutgoingCollector extends _OutgoingCollector {
  _OuterOutgoingCollector(super.out, {required super.ownElementId});

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    // Skip — the method has its own _ResolvedDeclaration with its own
    // outgoing set.
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    // Skip — each field variable has its own _ResolvedDeclaration.
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    // Constructors are not separately tracked, but we still don't want
    // to follow their bodies through the class — that would re-add
    // every method called from a constructor as an edge from the
    // class itself, defeating the per-member granularity.
  }

  @override
  void visitEnumConstantDeclaration(EnumConstantDeclaration node) {
    // Each enum constant has its own _ResolvedDeclaration.
  }
}

class _CollectionContext {
  _CollectionContext({
    required this.path,
    required this.lineInfo,
    required this.isLibPublic,
  });

  final String path;
  final LineInfo lineInfo;
  final bool isLibPublic;

  SourceLocation locOf(int offset) {
    final loc = lineInfo.getLocation(offset);
    return SourceLocation(
      path: path,
      line: loc.lineNumber,
      column: loc.columnNumber,
    );
  }
}

class _ResolvedDeclaration {
  _ResolvedDeclaration({
    required this.elementId,
    required this.record,
    required this.outgoingIds,
    required this.isInLibPublic,
    required this.isInstanceMember,
    required this.isOverride,
    required this.isObjectDunder,
    this.enclosingTypeElementId,
  });

  final int elementId;
  final DeclarationRecord record;
  final Set<int> outgoingIds;
  final bool isInLibPublic;
  final bool isInstanceMember;
  final bool isOverride;
  final bool isObjectDunder;

  /// Element id of the enclosing class / mixin / extension / enum, or
  /// `null` for top-level declarations. Used to propagate roots: when
  /// the enclosing type is rooted via an annotation keep-alive
  /// (e.g. `@JsonSerializable`, `@reflectiveTest`), every member is
  /// rooted too because the class's annotation typically signals
  /// reflective / generated-code use.
  final int? enclosingTypeElementId;
}
