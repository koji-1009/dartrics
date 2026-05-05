import '../models/source_location.dart';
import '../models/unused_declaration.dart';

/// Lightweight record for one top-level declaration in a Dart file.
///
/// Stores everything the reachability analysis needs:
/// - the declared simple name (matched against references and entry points),
/// - the declaration kind (for reporting),
/// - source location (for the report),
/// - the set of simple names referenced *anywhere inside* the declaration's
///   subtree — this is the BFS edge set,
/// - the simple-name list of `@`-annotations attached to the declaration
///   (so the detector can honor `@visibleForTesting`, etc.).
class DeclarationRecord {
  DeclarationRecord({
    required this.name,
    required this.kind,
    required this.location,
    required this.outgoingNames,
    required this.annotations,
    required this.hasVmEntryPointPragma,
  });

  final String name;
  final UnusedKind kind;
  final SourceLocation location;
  final Set<String> outgoingNames;
  final List<String> annotations;
  final bool hasVmEntryPointPragma;
}
