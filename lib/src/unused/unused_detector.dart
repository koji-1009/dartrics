import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import '../config/config.dart';
import '../models/source_location.dart';
import '../models/unused_declaration.dart';
import 'declaration_record.dart';
import 'entry_points.dart';
import 'reachability_graph.dart';
import 'resolved_reachability.dart';

/// Input record accepted by [UnusedDetector]. Both `ResolvedUnitResult`
/// and `parseString` results fit this shape.
typedef UnusedSource = ({String path, CompilationUnit unit, LineInfo lineInfo});

typedef _RootResolutionInputs = ({
  List<DeclarationRecord> declarations,
  Map<String, List<DeclarationRecord>> byName,
  List<UnusedSource> sources,
  UnusedConfig config,
});

/// Detects unreachable public declarations across the analyzed project
/// using a Periphery-style name-based reachability graph.
///
/// Limitations of the v1 implementation:
/// - Identifier matching is simple-name based; homonym methods on different
///   classes share an entry in the index and become reachable together.
///   This biases toward *under*-reporting (false negatives), which is a
///   safer default for a static reporter.
/// - Reflection (`dart:mirrors`), runtime-resolved names, and
///   code-generation entry points must be added to
///   [UnusedConfig.entryPoints] / [UnusedConfig.ignoreAnnotations] manually.
class UnusedDetector {
  const UnusedDetector();

  Future<List<UnusedDeclaration>> detect(
    List<UnusedSource> sources,
    UnusedConfig config,
  ) async {
    final declarations = _collectAll(sources);
    final byName = _indexByName(declarations);
    final roots = _resolveRoots((
      declarations: declarations,
      byName: byName,
      sources: sources,
      config: config,
    ));
    final reachable = reachableFrom(roots, byName);
    return _selectUnused(declarations, reachable);
  }

  /// Resolved-AST entry point. Reachability is computed over canonical
  /// [Element] ids rather than simple names, so homonym methods on
  /// different classes are independent nodes and SDK / dependency
  /// symbols never accidentally keep project declarations alive.
  ///
  /// Reportable kinds expand to `method`, `field`, `enumValue`, and
  /// `extension` members in addition to the parse-only top-level kinds —
  /// use [UnusedConfig.filter] (or `--filter` on the CLI) to narrow the
  /// emitted set.
  ///
  /// CLI commands route through this entry point; the parse-only
  /// [detect] above stays as a fallback for tests / embedders that
  /// don't want a real `AnalysisContextCollection`.
  Future<List<UnusedDeclaration>> detectResolved(
    List<ResolvedUnusedSource> sources,
    UnusedConfig config,
  ) async {
    return detectUnusedResolved(sources, config);
  }

  List<DeclarationRecord> _collectAll(List<UnusedSource> sources) {
    final out = <DeclarationRecord>[];
    for (final f in sources) {
      _collectFromUnit(f, out);
    }
    return out;
  }

  Map<String, List<DeclarationRecord>> _indexByName(
    List<DeclarationRecord> declarations,
  ) {
    final byName = <String, List<DeclarationRecord>>{};
    for (final d in declarations) {
      byName.putIfAbsent(d.name, () => <DeclarationRecord>[]).add(d);
    }
    return byName;
  }

  Set<DeclarationRecord> _resolveRoots(_RootResolutionInputs i) {
    final roots = <DeclarationRecord>{
      ...resolveEntryPoints(i.declarations, i.config),
    };
    if (i.config.excludeExported) {
      // Names referenced anywhere inside a "public" lib file (incl. its
      // export-directive `show` clauses) become additional roots so that
      // `export 'src/foo.dart' show Foo;` keeps `Foo` alive even though
      // no AST in the public file directly calls `Foo`.
      for (final name in _collectAmbientNames(i.sources)) {
        final hits = i.byName[name];
        if (hits != null) roots.addAll(hits);
      }
    }
    return roots;
  }

  Set<String> _collectAmbientNames(List<UnusedSource> sources) {
    final referenced = <String>{};
    for (final f in sources) {
      if (!_isLibraryPublic(f.path)) continue;
      f.unit.accept(_AmbientNameCollector(referenced));
    }
    return referenced;
  }

  List<UnusedDeclaration> _selectUnused(
    List<DeclarationRecord> declarations,
    Set<DeclarationRecord> reachable,
  ) {
    final unused = <UnusedDeclaration>[];
    for (final d in declarations) {
      if (d.name.startsWith('_')) continue; // analyzer's dead_code covers this
      if (reachable.contains(d)) continue;
      unused.add(
        UnusedDeclaration(kind: d.kind, name: d.name, location: d.location),
      );
    }
    return unused;
  }
}

void _collectFromUnit(UnusedSource source, List<DeclarationRecord> out) {
  SourceLocation locOf(int offset) {
    final loc = source.lineInfo.getLocation(offset);
    return SourceLocation(
      path: source.path,
      line: loc.lineNumber,
      column: loc.columnNumber,
    );
  }

  for (final decl in source.unit.declarations) {
    for (final entry in _entriesFor(decl)) {
      out.add(
        _buildRecord(entry: entry, location: locOf(entry.offset), decl: decl),
      );
    }
  }
}

class _Entry {
  _Entry(this.name, this.kind, this.offset);
  final String name;
  final UnusedKind kind;
  final int offset;
}

List<_Entry> _entriesFor(CompilationUnitMember decl) {
  switch (decl) {
    case FunctionDeclaration():
      return [_Entry(decl.name.lexeme, UnusedKind.function, decl.offset)];
    case ClassDeclaration():
      return [
        _Entry(decl.namePart.typeName.lexeme, UnusedKind.klass, decl.offset),
      ];
    case MixinDeclaration():
      return [_Entry(decl.name.lexeme, UnusedKind.klass, decl.offset)];
    case ExtensionDeclaration():
      return _entriesForExtension(decl);
    case EnumDeclaration():
      return [
        _Entry(
          decl.namePart.typeName.lexeme,
          UnusedKind.enumValue,
          decl.offset,
        ),
      ];
    case FunctionTypeAlias():
      return [_Entry(decl.name.lexeme, UnusedKind.typedef, decl.offset)];
    case GenericTypeAlias():
      return [_Entry(decl.name.lexeme, UnusedKind.typedef, decl.offset)];
    case TopLevelVariableDeclaration():
      return [
        for (final v in decl.variables.variables)
          _Entry(v.name.lexeme, UnusedKind.field, v.offset),
      ];
  }
  return const [];
}

List<_Entry> _entriesForExtension(ExtensionDeclaration decl) {
  final name = decl.name?.lexeme;
  if (name == null) return const [];
  return [_Entry(name, UnusedKind.extension, decl.offset)];
}

DeclarationRecord _buildRecord({
  required _Entry entry,
  required SourceLocation location,
  required CompilationUnitMember decl,
}) {
  final outgoing = <String>{};
  outgoing.addAll(_collectOutgoingNames(decl, ownName: entry.name));
  final annotations = decl.metadata.map((a) => a.name.name).toList();
  return DeclarationRecord(
    name: entry.name,
    kind: entry.kind,
    location: location,
    outgoingNames: outgoing,
    annotations: annotations,
    hasVmEntryPointPragma: decl.metadata.any(_isVmEntryPointPragma),
  );
}

Set<String> _collectOutgoingNames(AstNode node, {required String ownName}) {
  final ref = _ReferenceCollector(declarationOwnName: ownName)..walk(node);
  return ref.names;
}

bool _isVmEntryPointPragma(Annotation ann) {
  if (ann.name.name != 'pragma') return false;
  final args = ann.arguments?.arguments ?? const [];
  if (args.isEmpty) return false;
  final first = args.first;
  return first is StringLiteral && first.stringValue == 'vm:entry-point';
}

/// Collects every simple-name identifier and named-type reference inside an
/// AST subtree, *excluding* the declaration's own name (so a recursive call
/// doesn't make the function self-keep-alive).
class _ReferenceCollector extends RecursiveAstVisitor<void> {
  _ReferenceCollector({required this.declarationOwnName});
  final String declarationOwnName;
  final names = <String>{};

  void walk(AstNode node) => node.accept(this);

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final n = node.name;
    if (n != declarationOwnName) names.add(n);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    final n = node.name.lexeme;
    if (n != declarationOwnName) names.add(n);
    super.visitNamedType(node);
  }
}

/// File-wide name collector that walks both directives (export `show`
/// combinators included) and declarations.
class _AmbientNameCollector extends RecursiveAstVisitor<void> {
  _AmbientNameCollector(this.target);
  final Set<String> target;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    target.add(node.name);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    target.add(node.name.lexeme);
    super.visitNamedType(node);
  }
}

bool _isLibraryPublic(String path) {
  final unix = path.replaceAll(r'\', '/');
  if (!unix.contains('/lib/')) return false;
  if (unix.contains('/lib/src/')) return false;
  return true;
}
