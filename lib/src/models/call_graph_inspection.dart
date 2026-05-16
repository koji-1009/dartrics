import 'analysis_report.dart';
import 'call_graph_signal.dart';

/// Direction the inspector should follow from the anchor declaration.
/// `up` walks edges pointing at the anchor (its callers), `down` walks
/// edges originating from the anchor (its callees), `both` produces
/// the union.
enum InspectionDirection { up, down, both }

/// A neighbour node surfaced by the inspector, annotated with the
/// graph distance back to the anchor and the per-hop edge weight.
class InspectionNode {
  const InspectionNode({
    required this.signal,
    required this.depth,
    required this.incomingEdgeCount,
  });

  /// The signal for this declaration (file, scope, fan-in / fan-out
  /// totals computed against the whole project, not just the
  /// inspection subgraph).
  final CallGraphSignal signal;

  /// Number of edges separating this node from the anchor (1 = direct
  /// caller / callee, 2 = one hop further out, etc.).
  final int depth;

  /// Edge weight on the hop *into* this node from the closer side of
  /// the chain. For an upstream node this is the number of times that
  /// caller invokes the next-closer node toward the anchor; for a
  /// downstream node it is the number of times the next-closer node
  /// invokes this one.
  final int incomingEdgeCount;

  Map<String, Object?> toJson() => {
    'depth': depth,
    'incomingEdgeCount': incomingEdgeCount,
    'signal': signal.toJson(),
  };
}

/// One anchor declaration the inspector matched, along with its
/// upstream / downstream subgraphs. The CLI emits one match per
/// element-resolved hit when the user-supplied symbol resolves to
/// multiple project declarations (e.g. homonym methods on different
/// classes).
class InspectionMatch {
  const InspectionMatch({
    required this.anchor,
    required this.upstream,
    required this.downstream,
  });

  final CallGraphSignal anchor;

  /// Callers, ordered by depth ascending then by `fanInCallers`
  /// descending so the closest, most-connected callers float to the
  /// top.
  final List<InspectionNode> upstream;

  /// Callees, ordered by depth ascending then by `fanOutCallees`
  /// descending.
  final List<InspectionNode> downstream;

  Map<String, Object?> toJson() => {
    'anchor': anchor.toJson(),
    'upstream': upstream.map((n) => n.toJson()).toList(),
    'downstream': downstream.map((n) => n.toJson()).toList(),
  };
}

/// Result envelope returned by `dartrics inspect`. Always carries the
/// echoed query so a downstream consumer reading the JSON without the
/// invoking CLI line still understands the report's scope.
class InspectionResult {
  const InspectionResult({
    required this.query,
    required this.depth,
    required this.direction,
    required this.matches,
  });

  /// The symbol the user asked for (matched against [ScopeRef.name]
  /// — accepts both simple names like `foo` and dotted forms like
  /// `Foo.bar`).
  final String query;

  /// Depth bound that produced this result.
  final int depth;

  /// Direction bound that produced this result.
  final InspectionDirection direction;

  /// Every project-local declaration whose scope name matched the
  /// query, with its upstream / downstream neighbourhood.
  final List<InspectionMatch> matches;

  Map<String, Object?> toJson() => {
    'query': query,
    'depth': depth,
    'direction': direction.name,
    'matches': matches.map((m) => m.toJson()).toList(),
  };
}
