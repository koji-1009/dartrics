import 'package:dartrics/src/metrics/library/coupling.dart';
import 'package:dartrics/src/metrics/library/library_metric.dart';
import 'package:test/test.dart';

LibraryIndex _index() {
  return LibraryIndex.fromStats({
    '/p/lib/a.dart': LibraryStats(
      path: '/p/lib/a.dart',
      internalImports: {'/p/lib/b.dart', '/p/lib/c.dart'},
      totalClasses: 2,
      abstractClasses: 1,
    ),
    '/p/lib/b.dart': LibraryStats(
      path: '/p/lib/b.dart',
      internalImports: {'/p/lib/c.dart'},
      totalClasses: 1,
      abstractClasses: 0,
    ),
    '/p/lib/c.dart': LibraryStats(
      path: '/p/lib/c.dart',
      internalImports: <String>{},
      totalClasses: 1,
      abstractClasses: 0,
    ),
  });
}

void main() {
  test('Ce counts distinct internal imports', () {
    expect(
      const EfferentCoupling()
          .compute(LibraryMetricInput(path: '/p/lib/a.dart', index: _index())),
      2,
    );
    expect(
      const EfferentCoupling()
          .compute(LibraryMetricInput(path: '/p/lib/c.dart', index: _index())),
      0,
    );
  });

  test('Ca counts incoming internal imports', () {
    expect(
      const AfferentCoupling()
          .compute(LibraryMetricInput(path: '/p/lib/c.dart', index: _index())),
      2,
    );
    expect(
      const AfferentCoupling()
          .compute(LibraryMetricInput(path: '/p/lib/a.dart', index: _index())),
      0,
    );
  });

  test('Instability = Ce / (Ca + Ce)', () {
    final i = const Instability()
        .compute(LibraryMetricInput(path: '/p/lib/b.dart', index: _index()));
    // Ce(b) = 1 (imports c), Ca(b) = 1 (a imports b) → 0.5
    expect(i, 0.5);
  });

  test('Abstractness = abstract / total', () {
    expect(
      const Abstractness()
          .compute(LibraryMetricInput(path: '/p/lib/a.dart', index: _index())),
      0.5,
    );
  });

  test('D = |A + I - 1|', () {
    final input = LibraryMetricInput(path: '/p/lib/a.dart', index: _index());
    // Ce(a)=2, Ca(a)=0 → I = 1.0
    // A(a) = 0.5
    // D = |0.5 + 1.0 - 1| = 0.5
    expect(const DistanceFromMainSequence().compute(input), 0.5);
  });

  test('library with no inbound or outbound deps has I = 0', () {
    final i = const Instability().compute(
      LibraryMetricInput(path: '/p/lib/c.dart', index: _index()),
    );
    // Ce=0, Ca=2 → 0/2 = 0
    expect(i, 0);
  });
}
