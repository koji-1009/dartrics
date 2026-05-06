import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import 'dismissal.dart';

/// Recognised lines look like:
///
/// ```
/// // dartrics:dismiss <metric-id> reason="<text>"
/// ```
///
/// Anchored to the start of the comment lexeme so embedded URLs or
/// random tokens that contain `dartrics:dismiss` won't false-match.
final RegExp _dismissPattern = RegExp(
  r'^//\s*dartrics:dismiss\s+(\S+)\s+reason="([^"]*)"\s*$',
);

/// Scans every dismissal-eligible declaration in [unit] and returns the
/// `// dartrics:dismiss` comments that sit immediately above each one.
///
/// "Immediately above" means contiguous with the declaration's first
/// token: comments at lines `decl_line - 1`, `decl_line - 2`, … with no
/// blank lines in between. A blank line invalidates the rest of the
/// stack — anything above the blank is treated as a stray comment and
/// silently ignored (the same rule humans use to read the code).
List<Dismissal> scanCommentDismissals({
  required String path,
  required CompilationUnit unit,
  required LineInfo lineInfo,
}) {
  final visitor = _DismissalCommentVisitor(path: path, lineInfo: lineInfo);
  unit.accept(visitor);
  return visitor.dismissals;
}

class _DismissalCommentVisitor extends RecursiveAstVisitor<void> {
  _DismissalCommentVisitor({required this.path, required this.lineInfo});

  final String path;
  final LineInfo lineInfo;
  final List<Dismissal> dismissals = [];

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _scan(node, node.name.lexeme);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _scan(node, _methodScope(node, node.name.lexeme));
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final cls = _enclosingClass(node) ?? '<anonymous>';
    final name = node.name?.lexeme;
    final scope = name == null ? cls : '$cls.$name';
    _scan(node, scope);
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _scan(node, node.namePart.typeName.lexeme);
    super.visitClassDeclaration(node);
  }

  String _methodScope(MethodDeclaration method, String name) {
    final cls = _enclosingClass(method);
    return cls == null ? name : '$cls.$name';
  }

  String? _enclosingClass(AstNode node) {
    AstNode? parent = node.parent;
    while (parent != null) {
      if (parent is ClassDeclaration) return parent.namePart.typeName.lexeme;
      if (parent is MixinDeclaration) return parent.name.lexeme;
      if (parent is ExtensionDeclaration) {
        return parent.name?.lexeme ?? '<extension>';
      }
      if (parent is EnumDeclaration) return parent.namePart.typeName.lexeme;
      parent = parent.parent;
    }
    return null;
  }

  void _scan(Declaration decl, String scopeName) {
    final firstToken = decl.beginToken;
    final declLine = lineInfo.getLocation(firstToken.offset).lineNumber;
    final matches = <_CommentMatch>[];
    Token? c = firstToken.precedingComments;
    while (c != null) {
      final m = _dismissPattern.firstMatch(c.lexeme);
      if (m != null) {
        matches.add(
          _CommentMatch(
            line: lineInfo.getLocation(c.offset).lineNumber,
            metricId: m.group(1)!,
            reason: m.group(2)!,
          ),
        );
      }
      c = c.next;
    }
    // Adjacency walk from bottom-up: each accepted comment must sit on
    // exactly the line above the next accepted entity (declaration or
    // previous comment). The first blank-line gap stops the climb.
    var expected = declLine - 1;
    for (final m in matches.reversed) {
      if (m.line != expected) break;
      dismissals.add(
        Dismissal(
          file: path,
          scope: scopeName,
          metricId: m.metricId,
          reason: m.reason,
          source: DismissalSource.comment,
        ),
      );
      expected -= 1;
    }
  }
}

class _CommentMatch {
  _CommentMatch({
    required this.line,
    required this.metricId,
    required this.reason,
  });
  final int line;
  final String metricId;
  final String reason;
}
