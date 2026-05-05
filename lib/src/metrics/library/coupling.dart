import 'library_metric.dart';

/// Efferent Coupling (Ce, Martin 1994) — number of distinct libraries this
/// file depends on (excluding `dart:*` standard libraries).
class EfferentCoupling implements LibraryMetric {
  const EfferentCoupling();
  @override
  String get id => 'efferent-coupling';
  @override
  num compute(LibraryMetricInput input) => input.stats.internalImports.length;
}

/// Afferent Coupling (Ca, Martin 1994) — number of project-internal files
/// that import this one.
class AfferentCoupling implements LibraryMetric {
  const AfferentCoupling();
  @override
  String get id => 'afferent-coupling';
  @override
  num compute(LibraryMetricInput input) {
    return input.index.importers[input.path]?.length ?? 0;
  }
}

/// Instability (I, Martin 1994) — `Ce / (Ca + Ce)`. Ranges over `[0, 1]`,
/// where 1 means maximally unstable (the file depends on everything but is
/// depended on by nothing) and 0 means maximally stable.
class Instability implements LibraryMetric {
  const Instability();
  @override
  String get id => 'instability';
  @override
  num compute(LibraryMetricInput input) {
    final ce = const EfferentCoupling().compute(input);
    final ca = const AfferentCoupling().compute(input);
    final total = ce + ca;
    if (total == 0) return 0;
    return ce / total;
  }
}

/// Abstractness (A, Martin 1994) — fraction of class-like types in this
/// file that are abstract or mixins.
class Abstractness implements LibraryMetric {
  const Abstractness();
  @override
  String get id => 'abstractness';
  @override
  num compute(LibraryMetricInput input) {
    final total = input.stats.totalClasses;
    if (total == 0) return 0;
    return input.stats.abstractClasses / total;
  }
}

/// Distance from the Main Sequence (D, Martin 1994) — `|A + I − 1|`.
/// Values close to 0 indicate a healthy balance between stability and
/// abstractness. Values close to 1 mark either a "zone of pain" (concrete
/// + stable) or a "zone of uselessness" (abstract + unstable).
class DistanceFromMainSequence implements LibraryMetric {
  const DistanceFromMainSequence();
  @override
  String get id => 'distance-from-main-sequence';
  @override
  num compute(LibraryMetricInput input) {
    final a = const Abstractness().compute(input);
    final i = const Instability().compute(input);
    return (a + i - 1).abs();
  }
}
