import '../metric.dart';
import 'library_metric.dart';

/// Efferent Coupling (Ce, Martin 1994) — number of distinct libraries this
/// file depends on (excluding `dart:*` standard libraries).
class EfferentCoupling extends LibraryMetric {
  const EfferentCoupling();
  @override
  String get id => 'efferent-coupling';
  @override
  String get rationale =>
      'Efferent coupling `Cₑ` (Martin, *OO Design Quality Metrics*, '
      '1994) is the number of distinct libraries this file depends on, '
      'excluding the `dart:*` standard library. Files with very high '
      '`Cₑ` are sensitive to changes in many other places — they pay '
      'a cost on every refactor sweep.';

  @override
  List<String> get refactorHints => const [
    'Hide a cluster of related dependencies behind a single facade package and depend on the facade instead.',
    'Move outgoing dependencies that exist only to support one method into that method\'s file.',
  ];
  @override
  num compute(LibraryMetricInput input) => input.stats.internalImports.length;
}

/// Afferent Coupling (Ca, Martin 1994) — number of project-internal files
/// that import this one.
class AfferentCoupling extends LibraryMetric {
  const AfferentCoupling();
  @override
  String get id => 'afferent-coupling';
  @override
  String get rationale =>
      'Afferent coupling `Cₐ` (Martin 1994) is the number of '
      'project-internal files that import this one. High `Cₐ` means '
      'the file is depended on by many others — changes here ripple '
      'broadly, so the file should be stable and well-typed.';

  @override
  List<String> get refactorHints => const [
    'If `Cₐ` is high, treat the file as a public contract: keep it small, well-documented, and change-averse.',
    'Move volatile implementation details out into a separate file with low `Cₐ` so the high-`Cₐ` file holds only stable types.',
  ];
  @override
  num compute(LibraryMetricInput input) {
    return input.index.importers[input.path]?.length ?? 0;
  }
}

/// Instability (I, Martin 1994) — `Ce / (Ca + Ce)`. Ranges over `[0, 1]`,
/// where 1 means maximally unstable (the file depends on everything but is
/// depended on by nothing) and 0 means maximally stable.
class Instability extends LibraryMetric {
  const Instability();
  @override
  String get id => 'instability';
  @override
  String get rationale =>
      'Instability `I = Cₑ / (Cₐ + Cₑ)` (Martin 1994) is a 0–1 ratio. '
      '`I = 1` means the file depends on others but nothing depends '
      'on it (maximally unstable), and `I = 0` means many files '
      'depend on this one but it depends on nothing (maximally '
      'stable). Martin\'s "Stable Dependencies Principle" says '
      'dependencies should always point towards more-stable files.';

  @override
  List<String> get refactorHints => const [
    'Where a stable file imports an unstable one, invert the dependency by introducing an interface in the stable side.',
    'Either accept the file as a leaf consumer (high `I`, OK) or as a stable contract (low `I`, also OK) — middling values are where churn lives.',
  ];
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
class Abstractness extends LibraryMetric {
  const Abstractness();
  @override
  String get id => 'abstractness';
  @override
  String get rationale =>
      'Abstractness `A` (Martin 1994) is the fraction of class-like '
      'declarations in the file that are abstract (`abstract class` '
      'or `mixin`). Combined with `Instability`, it places each file '
      'on the A–I plane that defines Martin\'s "Main Sequence".';

  @override
  List<String> get refactorHints => const [
    'If a stable file has low `A`, consider extracting interfaces so consumers depend on contracts rather than concrete types.',
    'If an unstable file has high `A`, fold the abstractions back into concrete classes — abstraction without consumers is overhead.',
  ];
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
class DistanceFromMainSequence extends LibraryMetric {
  const DistanceFromMainSequence();
  @override
  String get id => 'distance-from-main-sequence';
  @override
  MetricPolarity get polarity => MetricPolarity.down;
  @override
  String get rationale =>
      'Distance from the Main Sequence `D = |A + I − 1|` (Martin 1994) '
      'measures how far the file sits from the line `A + I = 1` on '
      'the A–I plane. `D = 0` is the ideal balance; `D ≈ 1` lands '
      'either in the "zone of pain" (stable + concrete) or the "zone '
      'of uselessness" (unstable + abstract).';

  @override
  List<String> get refactorHints => const [
    'Pain zone (stable + concrete): extract an abstract layer that consumers depend on instead.',
    'Useless zone (unstable + abstract): collapse the abstraction into the consumers that actually need it.',
  ];
  @override
  num compute(LibraryMetricInput input) {
    final a = const Abstractness().compute(input);
    final i = const Instability().compute(input);
    return (a + i - 1).abs();
  }
}
