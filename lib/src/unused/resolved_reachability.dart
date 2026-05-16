import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/line_info.dart';

import '../config/config.dart';
import '../models/analysis_report.dart';
import '../models/call_graph_signal.dart';
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

/// Derives per-declaration call-graph signals (fan-in / fan-out) from
/// the same element-resolved reachability pass that powers
/// [detectUnusedResolved]. Signals are *reference information* — no
/// thresholds, no severity — so the reporter layer surfaces them in a
/// dedicated `signals:` block instead of mixing them with violations.
///
/// Fan-in counts edges arriving at a declaration; `fanInCallers` is the
/// distinct-caller count and `fanInCalls` is the raw invocation total
/// (calling `foo()` three times in `A` contributes 1 to `fanInCallers`
/// and 3 to `fanInCalls`). Fan-out is the dual, restricted to
/// project-local targets — references that resolved to SDK or
/// dependency package elements are dropped so the signal stays at
/// "how coupled is this scope inside my codebase".
///
/// Walks the AST once, independently of [detectUnusedResolved]; both
/// callers run on the same `ResolvedUnitResult` list so the cost is in
/// the AST walk, not the reachability work itself.
List<CallGraphSignal> computeCallGraphSignals(
  List<ResolvedUnusedSource> sources,
) {
  final declarations = <_ResolvedDeclaration>[];
  for (final s in sources) {
    _collectFromUnit(s, declarations);
  }
  final byId = <int, _ResolvedDeclaration>{
    for (final d in declarations) d.elementId: d,
  };

  // Build the inverse index: target element id → (distinct callers,
  // total call-site edge count). Only counts callers that are
  // themselves project-local declarations — references from outside
  // the analyzed surface aren't visible in `declarations`, so they
  // never land in this map (which is the correct behaviour for an
  // intra-project coupling metric).
  final incomingCallers = <int, Set<int>>{};
  final incomingCalls = <int, int>{};
  for (final d in declarations) {
    for (final entry in d.outgoingCounts.entries) {
      incomingCallers.putIfAbsent(entry.key, () => <int>{}).add(d.elementId);
      incomingCalls.update(
        entry.key,
        (n) => n + entry.value,
        ifAbsent: () => entry.value,
      );
    }
  }

  final out = <CallGraphSignal>[];
  for (final d in declarations) {
    var fanOutCallees = 0;
    var fanOutCalls = 0;
    for (final entry in d.outgoingCounts.entries) {
      if (!byId.containsKey(entry.key)) continue;
      fanOutCallees += 1;
      fanOutCalls += entry.value;
    }
    out.add(
      CallGraphSignal(
        file: d.record.location.path,
        scope: _scopeRefFor(d, byId),
        fanInCallers: incomingCallers[d.elementId]?.length ?? 0,
        fanInCalls: incomingCalls[d.elementId] ?? 0,
        fanOutCallees: fanOutCallees,
        fanOutCalls: fanOutCalls,
      ),
    );
  }
  return out;
}

/// Maps `_ResolvedDeclaration` (UnusedKind-tagged) into the
/// `ScopeRef` shape the rest of the report uses (`ScopeKind` +
/// dotted scope name). Class members come back as
/// `EnclosingType.memberName` when the enclosing type is in scope so
/// AI loops don't have to disambiguate homonyms by location alone.
ScopeRef _scopeRefFor(
  _ResolvedDeclaration d,
  Map<int, _ResolvedDeclaration> byId,
) {
  final encl = d.enclosingTypeElementId;
  final qualified = (encl != null && byId.containsKey(encl))
      ? '${byId[encl]!.record.name}.${d.record.name}'
      : d.record.name;
  return ScopeRef(
    kind: _scopeKindFor(d.record.kind, isInstanceMember: d.isInstanceMember),
    name: qualified,
    location: d.record.location,
  );
}

ScopeKind _scopeKindFor(UnusedKind kind, {required bool isInstanceMember}) {
  switch (kind) {
    case UnusedKind.function:
      return ScopeKind.function;
    case UnusedKind.method:
      return ScopeKind.method;
    case UnusedKind.klass:
    case UnusedKind.extension:
      return ScopeKind.klass;
    case UnusedKind.field:
    case UnusedKind.enumValue:
      return isInstanceMember ? ScopeKind.method : ScopeKind.function;
    case UnusedKind.typedef:
      return ScopeKind.function;
  }
}

/// Translates the raw `filter` strings from [UnusedConfig] into a kind
/// set. Returns `null` when no filter is configured (= keep every kind).
/// Throws [FormatException] for unknown names so the caller (CLI /
/// config loader) can surface a usage error rather than silently
/// dropping every entry.
///
/// Accepted names are exactly [unusedFilterKindNames] — the same
/// canonical strings the JSON `kind` field uses. The two Dart-keyword
/// quirks (`klass`, `enumValue`) are translated through
/// [unusedKindFromJsonName].
Set<UnusedKind>? parseUnusedFilter(List<String> filter) {
  if (filter.isEmpty) return null;
  final out = <UnusedKind>{};
  for (final raw in filter) {
    final name = raw.trim();
    if (name.isEmpty) continue;
    final match = unusedKindFromJsonName(name);
    if (match == null) {
      throw FormatException(
        'unused.filter: unknown kind "$raw". valid kinds: '
        '${unusedFilterKindNames.join(", ")}',
      );
    }
    out.add(match);
  }
  return out.isEmpty ? null : out;
}

/// Kind names accepted by `--filter`, in the order they should appear
/// in `--help` text. Identical to the JSON `kind` field's value
/// space — `unusedKindJsonName(kind)` returns one of these.
const List<String> unusedFilterKindNames = [
  'function',
  'method',
  'class',
  'field',
  'typedef',
  'enum',
  'extension',
];

Set<int> _bfs(Iterable<int> roots, Map<int, _ResolvedDeclaration> byId) {
  final visited = <int>{};
  final queue = <int>[...roots];
  while (queue.isNotEmpty) {
    final id = queue.removeLast();
    if (!visited.add(id)) continue;
    final next = byId[id];
    if (next == null) continue;
    for (final outId in next.outgoingCounts.keys) {
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
      outgoingCounts: _classOutgoing(decl, members, element.id),
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
Map<int, int> _classOutgoing(
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
      final ctor = _collectOutgoing(m, ownElementId: ownElementId);
      ctor.forEach((id, count) {
        out.update(id, (n) => n + count, ifAbsent: () => count);
      });
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
      outgoingCounts: _classOutgoing(decl, decl.body.members, element.id),
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
      outgoingCounts: _classOutgoing(decl, decl.body.members, element.id),
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
        outgoingCounts: _collectOutgoing(c, ownElementId: cElement.id),
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
      outgoingCounts: _collectOutgoing(decl, ownElementId: id),
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
        outgoingCounts: _collectVariableOutgoing(
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
/// [VariableDeclarationList]. The list-level shared type annotation
/// and the parent declaration's metadata sit on the parent, not on
/// each [VariableDeclaration], so per-variable emission walks them
/// explicitly to keep references on those nodes in scope.
Map<int, int> _collectVariableOutgoing({
  required VariableDeclaration variable,
  required TypeAnnotation? sharedType,
  required NodeList<Annotation> metadata,
  required int ownElementId,
}) {
  final out = <int, int>{};
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
      outgoingCounts: _collectOutgoing(decl, ownElementId: canonical.id),
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
        outgoingCounts: _collectVariableOutgoing(
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
      outgoingCounts: _collectOutgoing(node, ownElementId: element.id),
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

Map<int, int> _collectOutgoing(AstNode node, {required int ownElementId}) {
  final out = <int, int>{};
  node.accept(_OutgoingCollector(out, ownElementId: ownElementId));
  return out;
}

/// Same as [_collectOutgoing] but skips descent into nested class
/// members. Used when walking the parts of a class / mixin /
/// extension / enum declaration that contribute the *type*'s own
/// outgoing edges (annotations, type parameters, extends / implements
/// / with clauses) — without double-counting the references that
/// each member already tracks on its own.
Map<int, int> _collectOutgoingExcludingMembers(
  AstNode node, {
  required int ownElementId,
}) {
  final out = <int, int>{};
  node.accept(_OuterOutgoingCollector(out, ownElementId: ownElementId));
  return out;
}

/// Walks an AST subtree and records every project-local element id it
/// references, keyed on element id with the per-edge invocation count
/// as the value. References to off-project elements (SDK,
/// dependencies) land in the map as their own ids and are dropped
/// during BFS because they aren't keys in `byId`; the counts on those
/// orphan entries still feed the fan-in / fan-out signals because
/// those are derived from `byId` membership before summing.
class _OutgoingCollector extends RecursiveAstVisitor<void> {
  _OutgoingCollector(this.out, {required this.ownElementId});

  final Map<int, int> out;
  final int ownElementId;

  void _record(Element? referent) {
    if (referent == null) return;
    var e = referent.baseElement.nonSynthetic;
    while (true) {
      if (e.id != ownElementId) {
        out.update(e.id, (n) => n + 1, ifAbsent: () => 1);
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
    // Recording `constructorName.element` covers the constructor and
    // (via the enclosing-element walk in [_record]) the class. The
    // default `super` descent would then re-visit the type's identifier
    // and double-count it; walk the type explicitly instead so the
    // edge count stays equal to the textual reference count.
    _record(node.constructorName.element);
    node.constructorName.type.accept(this);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _record(node.constructorName.element);
    node.constructorName.type.accept(this);
    node.argumentList.accept(this);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _record(node.methodName.element);
    node.target?.accept(this);
    node.typeArguments?.accept(this);
    node.argumentList.accept(this);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    _record(node.propertyName.element);
    node.target?.accept(this);
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

  @override
  void visitPatternField(PatternField node) {
    // Object-pattern destructuring (`case Foo(:final bar)`) accesses
    // the field via [PatternField.element]; the synthetic accessor
    // doesn't show up through any other AST hook.
    _record(node.element);
    super.visitPatternField(node);
  }
}

/// Variant of [_OutgoingCollector] that does NOT descend into class
/// member declarations (methods, fields, constructors, enum
/// constants). The outer container's outgoing edge set is therefore
/// scoped to the type-level surface (annotations, supertypes,
/// generics) — every member declaration registers its own edges on a
/// separate node, so re-walking the body would double-count and, more
/// importantly, make the container's reachability transitively root
/// every member it owns. The four overrides below are intentionally
/// empty (no `super` call) so the outer pass stops at each member's
/// boundary.
class _OuterOutgoingCollector extends _OutgoingCollector {
  _OuterOutgoingCollector(super.out, {required super.ownElementId});

  @override
  void visitMethodDeclaration(MethodDeclaration node) {}

  @override
  void visitFieldDeclaration(FieldDeclaration node) {}

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {}

  @override
  void visitEnumConstantDeclaration(EnumConstantDeclaration node) {}
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
    required this.outgoingCounts,
    required this.isInLibPublic,
    required this.isInstanceMember,
    required this.isOverride,
    required this.isObjectDunder,
    this.enclosingTypeElementId,
  });

  final int elementId;
  final DeclarationRecord record;

  /// Project-local element ids this declaration references, keyed on
  /// the target id with the per-edge invocation count as the value.
  /// Counts feed the fan-in / fan-out signals; BFS reachability only
  /// looks at the keys.
  final Map<int, int> outgoingCounts;

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
