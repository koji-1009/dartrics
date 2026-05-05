import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import '../config/config.dart';
import '../models/source_location.dart';
import '../models/unused_declaration.dart';
import 'declaration_record.dart';
import 'entry_points.dart';
import 'reachability_graph.dart';

/// Input record accepted by [UnusedDetector]. Both `ResolvedUnitResult` and
/// `parseString`-style results fit this shape, so tests can drive the
/// detector with cheap parse-only fixtures.
typedef UnusedSource = ({String path, CompilationUnit unit, LineInfo lineInfo});

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
    final declarations = <DeclarationRecord>[];
    for (final f in sources) {
      _collectFromUnit(f.path, f.unit, f.lineInfo, declarations);
    }

    final byName = <String, List<DeclarationRecord>>{};
    for (final d in declarations) {
      byName.putIfAbsent(d.name, () => <DeclarationRecord>[]).add(d);
    }

    final roots = <DeclarationRecord>{
      ...resolveEntryPoints(declarations, config),
    };
    if (config.excludeExported) {
      // Names referenced anywhere inside a "public" lib file (incl. its
      // export-directive `show` clauses) are treated as additional roots.
      // This lets `export 'src/foo.dart' show Foo;` keep `Foo` alive even
      // though no AST in the public file calls `Foo` directly.
      final referenced = <String>{};
      for (final f in sources) {
        if (!_isLibraryPublic(f.path)) continue;
        f.unit.accept(_AmbientNameCollector(referenced));
      }
      for (final name in referenced) {
        final hits = byName[name];
        if (hits != null) roots.addAll(hits);
      }
    }
    final reachable = reachableFrom(roots, byName);

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

void _collectFromUnit(
  String path,
  CompilationUnit unit,
  LineInfo lineInfo,
  List<DeclarationRecord> out,
) {
  SourceLocation locOf(int offset) {
    final loc = lineInfo.getLocation(offset);
    return SourceLocation(
      path: path,
      line: loc.lineNumber,
      column: loc.columnNumber,
    );
  }

  for (final decl in unit.declarations) {
    final entries = _entriesFor(decl);
    for (final entry in entries) {
      out.add(
        _record(
          name: entry.name,
          kind: entry.kind,
          location: locOf(entry.offset),
          bodyNode: decl,
          metadata: decl.metadata,
        ),
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
  if (decl is FunctionDeclaration) {
    return [_Entry(decl.name.lexeme, UnusedKind.function, decl.offset)];
  }
  if (decl is ClassDeclaration) {
    return [
      _Entry(decl.namePart.typeName.lexeme, UnusedKind.klass, decl.offset),
    ];
  }
  if (decl is MixinDeclaration) {
    return [_Entry(decl.name.lexeme, UnusedKind.klass, decl.offset)];
  }
  if (decl is ExtensionDeclaration) {
    final n = decl.name?.lexeme;
    return n == null
        ? const []
        : [_Entry(n, UnusedKind.extension, decl.offset)];
  }
  if (decl is EnumDeclaration) {
    return [
      _Entry(decl.namePart.typeName.lexeme, UnusedKind.enumValue, decl.offset),
    ];
  }
  if (decl is FunctionTypeAlias) {
    return [_Entry(decl.name.lexeme, UnusedKind.typedef, decl.offset)];
  }
  if (decl is GenericTypeAlias) {
    return [_Entry(decl.name.lexeme, UnusedKind.typedef, decl.offset)];
  }
  if (decl is TopLevelVariableDeclaration) {
    return [
      for (final v in decl.variables.variables)
        _Entry(v.name.lexeme, UnusedKind.field, v.offset),
    ];
  }
  return const [];
}

DeclarationRecord _record({
  required String name,
  required UnusedKind kind,
  required SourceLocation location,
  required AstNode bodyNode,
  required NodeList<Annotation> metadata,
}) {
  final outgoing = <String>{};
  final ref = _ReferenceCollector(declarationOwnName: name)..walk(bodyNode);
  outgoing.addAll(ref.names);

  final annotations = <String>[];
  var hasVmEntryPoint = false;
  for (final ann in metadata) {
    final aname = ann.name.name;
    annotations.add(aname);
    if (aname == 'pragma') {
      final args = ann.arguments?.arguments ?? const [];
      if (args.isNotEmpty) {
        final first = args.first;
        if (first is StringLiteral && first.stringValue == 'vm:entry-point') {
          hasVmEntryPoint = true;
        }
      }
    }
  }

  return DeclarationRecord(
    name: name,
    kind: kind,
    location: location,
    outgoingNames: outgoing,
    annotations: annotations,
    hasVmEntryPointPragma: hasVmEntryPoint,
  );
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
