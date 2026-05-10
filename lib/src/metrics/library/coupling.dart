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
  List<String> get references => const [
    'Martin, R. C. (1994). OO Design Quality Metrics: An Analysis of Dependencies. Self-published essay, August 14, 1994 (rev. June 20, 1995); cross-posted to comp.object and comp.lang.c++. Content later folded into Martin (2002), Agile Software Development: Principles, Patterns, and Practices, Ch. 28, Prentice Hall.',
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
  List<String> get references => const [
    'Martin, R. C. (1994). OO Design Quality Metrics: An Analysis of Dependencies. Self-published essay, August 14, 1994 (rev. June 20, 1995); cross-posted to comp.object and comp.lang.c++. Content later folded into Martin (2002), Agile Software Development: Principles, Patterns, and Practices, Ch. 28, Prentice Hall.',
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
  List<String> get references => const [
    'Martin, R. C. (1994). OO Design Quality Metrics: An Analysis of Dependencies. Self-published essay, August 14, 1994 (rev. June 20, 1995); cross-posted to comp.object and comp.lang.c++. Content later folded into Martin (2002), Agile Software Development: Principles, Patterns, and Practices, Ch. 28, Prentice Hall.',
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
