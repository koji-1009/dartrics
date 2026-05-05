import 'dart:collection';

import 'declaration_record.dart';

/// BFS over the simple-name reference graph rooted at [entryPoints].
///
/// Each declaration's `outgoingNames` set is treated as the simple-name
/// adjacency list; an edge is followed if any declaration in the index
/// shares that name. Multiple declarations sharing a name (different
/// classes' homonym methods) all become reachable together — this is a
/// known false-negative direction documented at the call site in
/// `UnusedDetector`.
Set<DeclarationRecord> reachableFrom(
  Iterable<DeclarationRecord> entryPoints,
  Map<String, List<DeclarationRecord>> byName,
) {
  final state = _BfsState(byName);
  state.queue.addAll(entryPoints);
  while (state.queue.isNotEmpty) {
    final current = state.queue.removeFirst();
    if (state.visited.add(current)) state.enqueueNeighborsOf(current);
  }
  return state.visited;
}

class _BfsState {
  _BfsState(this.byName);
  final Map<String, List<DeclarationRecord>> byName;
  final Set<DeclarationRecord> visited = {};
  final Queue<DeclarationRecord> queue = Queue<DeclarationRecord>();

  void enqueueNeighborsOf(DeclarationRecord current) {
    for (final name in current.outgoingNames) {
      final candidates = byName[name];
      if (candidates == null) continue;
      for (final next in candidates) {
        if (!visited.contains(next)) queue.add(next);
      }
    }
  }
}
