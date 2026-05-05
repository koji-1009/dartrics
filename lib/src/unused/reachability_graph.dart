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
  final visited = <DeclarationRecord>{};
  final queue = Queue<DeclarationRecord>.from(entryPoints);
  while (queue.isNotEmpty) {
    final d = queue.removeFirst();
    if (!visited.add(d)) continue;
    for (final name in d.outgoingNames) {
      final candidates = byName[name];
      if (candidates == null) continue;
      for (final next in candidates) {
        if (!visited.contains(next)) queue.add(next);
      }
    }
  }
  return visited;
}
